// deno-lint-ignore-file no-import-prefix
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0"
import { initializeApp, cert } from "npm:firebase-admin@11.11.1/app"
import { getMessaging } from "npm:firebase-admin@11.11.1/messaging"

const firebaseConfigStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}';
const firebaseConfig = JSON.parse(firebaseConfigStr);

if (Object.keys(firebaseConfig).length > 0) {
  try {
    initializeApp({ credential: cert(firebaseConfig) });
  } catch (_error) {
    // 忽略重複初始化的錯誤
  }
}

serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const record = payload.record;
    
    const oldRecord = payload.old_record;
    const tableName = payload.table;

    const deviceId = record?.device_id || record?.sn; 

    if (!deviceId) {
      console.log("❌ 收到無效的請求：找不到 device_id 或 sn"); 
      return new Response("No device_id found", { status: 400 });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // ==========================================
    // 🚨 優先處理：來自 devices 表的觸發 (包含設備上下線、市電狀態改變)
    // ==========================================
    if (tableName === 'devices') {
      let isProcessed = false;

      // ----------------------------------------
      // 1. 設備上下線強制通知 (is_online 變化)
      // ----------------------------------------
      if (oldRecord && oldRecord.is_online !== record.is_online) {
        isProcessed = true;
        const pushMessages = [];
        
        const twTime = new Intl.DateTimeFormat('zh-TW', {
          timeZone: 'Asia/Taipei',
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
          second: '2-digit',
          hour12: false
        }).format(new Date());

        if (record.is_online === false) {
          pushMessages.push(`儲能系統已離線\n發生時間：${twTime}`);
        } else if (record.is_online === true) {
          pushMessages.push(`儲能系統已重新連線\n發生時間：${twTime}`);
        }

        if (pushMessages.length > 0) {
          console.log(`💬 [強制推播] 設備 ${deviceId} 連線狀態改變: ${pushMessages[0]}`);
          
          const pushTitle = "⚠️ 儲能系統連線狀態";
          const pushBody = pushMessages.join('\n');

          // 🎯 新增 1：寫入歷史紀錄至 device_notifications
          await supabaseAdmin.from('device_notifications').insert({
            device_id: deviceId,
            title: pushTitle,
            message: pushBody
          });

          const { data: profile } = await supabaseAdmin
            .from('profiles')
            .select('fcm_token')
            .eq('id', record.user_id) 
            .single();

          if (profile?.fcm_token) {
            try {
              await getMessaging().send({
                token: profile.fcm_token,
                notification: {
                  title: pushTitle,
                  body: pushBody,
                },
              });
              console.log(`✅ [推播成功] 已發送上下線強制通知給使用者: ${record.user_id}`);
            } catch (fcmErr) {
              console.error('❌ [FCM 發送失敗]:', fcmErr);
            }
          }
        }
      }

      // ----------------------------------------
      // 2. 一般處理：市電斷線/復線通知 (檢查 alert_states 變化)
      // ----------------------------------------
      const oldGridOff = oldRecord?.alert_states?.is_grid_off;
      const newGridOff = record?.alert_states?.is_grid_off;

      if (oldGridOff !== undefined && newGridOff !== undefined && oldGridOff !== newGridOff) {
        isProcessed = true;
        const userWantsGridAlerts = record?.notification_settings?.grid_off === true;

        if (userWantsGridAlerts) {
          const pushMessages = [];
          const twTime = new Intl.DateTimeFormat('zh-TW', {
            timeZone: 'Asia/Taipei',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false
          }).format(new Date());

          if (newGridOff === true) {
            pushMessages.push(`市電已中斷，目前使用電池供電中\n發生時間：${twTime}`);
          } else {
            pushMessages.push(`市電已恢復，目前已切換回市電\n發生時間：${twTime}`);
          }

          console.log(`💬 [市電推播] 設備 ${deviceId} 狀態改變: ${pushMessages[0]}`);
          
          const pushTitle = newGridOff ? "⚠️ 市電停電" : "🔌 市電復電";
          const pushBody = pushMessages.join('\n');

          // 🎯 新增 2：寫入歷史紀錄至 device_notifications
          await supabaseAdmin.from('device_notifications').insert({
            device_id: deviceId,
            title: pushTitle,
            message: pushBody
          });

          const { data: profile } = await supabaseAdmin
            .from('profiles')
            .select('fcm_token')
            .eq('id', record.user_id) 
            .single();

          if (profile?.fcm_token) {
            try {
              await getMessaging().send({
                token: profile.fcm_token,
                notification: {
                  title: pushTitle,
                  body: pushBody,
                },
              });
              console.log(`✅ [推播成功] 已發送市電狀態通知給使用者`);
            } catch (fcmErr) {
              console.error('❌ [FCM 發送失敗]:', fcmErr);
            }
          }
        } else {
          console.log(`ℹ️ [推播略過] 設備 ${deviceId} 市電狀態改變，但使用者已關閉該項通知。`);
        }
      }

// ----------------------------------------
      // 3. 惡劣天氣備援模式切換 (檢查 is_storm_backup_mode 變化)
      // ----------------------------------------
      const oldStormMode = oldRecord?.is_storm_backup_mode;
      const newStormMode = record?.is_storm_backup_mode;

      if (oldStormMode !== undefined && newStormMode !== undefined && oldStormMode !== newStormMode) {
        isProcessed = true;
        
        const twTime = new Intl.DateTimeFormat('zh-TW', {
          timeZone: 'Asia/Taipei',
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
          second: '2-digit',
          hour12: false
        }).format(new Date());

        // 設定推播的標題與內容
        const pushTitle = newStormMode ? "🛡️ 惡劣天氣備援模式已開啟" : "✅ 惡劣天氣備援模式已關閉";
        const pushBody = newStormMode 
          ? `已暫停時間電價(TOU)排程，並盡可能維持電池在高儲備量狀態。\n操作時間：${twTime}`
          : `已解除惡劣天氣備援模式，恢復正常時間電價(TOU)排程。\n操作時間：${twTime}`;

        console.log(`💬 [備援模式推播] 設備 ${deviceId} 狀態改變: ${pushTitle}`);

        // 🎯 寫入歷史紀錄至 device_notifications (通知中心)
        await supabaseAdmin.from('device_notifications').insert({
          device_id: deviceId,
          title: pushTitle,
          message: pushBody
        });

        // 🎯 發送 FCM 手機推播
        const { data: profile } = await supabaseAdmin
          .from('profiles')
          .select('fcm_token')
          .eq('id', record.user_id) 
          .single();

        if (profile?.fcm_token) {
          try {
            await getMessaging().send({
              token: profile.fcm_token,
              notification: {
                title: pushTitle,
                body: pushBody,
              },
            });
            console.log(`✅ [推播成功] 已發送惡劣天氣備援模式狀態通知`);
          } catch (fcmErr) {
            console.error('❌ [FCM 發送失敗]:', fcmErr);
          }
        }
      }

      if (isProcessed) {
        return new Response(JSON.stringify({ success: true, message: "Devices table update processed" }), { headers: { "Content-Type": "application/json" } });
      } else {
        return new Response(JSON.stringify({ success: true, message: "Ignored unrelated devices update" }), { headers: { "Content-Type": "application/json" } });
      }
    }

    // ==========================================
    // 📊 以下為原本的遙測數據處理 (來自 telemetry_* 表)
    // ==========================================
    let capacity = record.battery_capacity; 
    let linePowerDir = record.line_power_direction; 
    let solar1 = record.solar1_input_power; 
    let solar2 = record.solar2_input_power; 
    let loadPercent = record.ac_out_power_percentage; 

    if (capacity === undefined || linePowerDir === undefined) { 
      const { data: testData } = await supabaseAdmin 
        .from('telemetry_test') 
        .select('battery_capacity, line_power_direction') 
        .eq('device_id', deviceId) 
        .order('id', { ascending: false }) 
        .limit(1) 
        .maybeSingle(); 
      
      capacity = capacity ?? testData?.battery_capacity ?? 0; 
      linePowerDir = linePowerDir ?? testData?.line_power_direction ?? 1; 
    } 

    if (solar1 === undefined || loadPercent === undefined) { 
      const { data: invData } = await supabaseAdmin 
        .from('telemetry_inv_ps') 
        .select('solar1_input_power, solar2_input_power, ac_out_power_percentage') 
        .eq('device_id', deviceId) 
        .order('id', { ascending: false }) 
        .limit(1) 
        .maybeSingle(); 
        
      solar1 = solar1 ?? invData?.solar1_input_power ?? 0; 
      solar2 = solar2 ?? invData?.solar2_input_power ?? 0; 
      loadPercent = loadPercent ?? invData?.ac_out_power_percentage ?? 0; 
    } 

    const totalSolar = solar1 + solar2; 

    console.log(`\n📥 [跨表資料整合成功] SN: ${deviceId}`); 
    console.log(`🔋 電池: ${capacity}% | ⚡ 市電方向: ${linePowerDir} | ☀️ 太陽能: ${totalSolar}W | 🏠 負載: ${loadPercent}%`); 

    const { data: device, error: devError } = await supabaseAdmin 
      .from('devices') 
      .select('id, user_id, notification_settings, alert_states') 
      .eq('sn', deviceId) 
      .single(); 

    if (devError || !device) return new Response("Device not found", { status: 404 }); 

    const settings = device.notification_settings || {}; 
    const oldStates = device.alert_states || {}; 
    const newStates = { ...oldStates };  
    const pushMessages: string[] = []; 

    if (capacity === 100 && !oldStates.is_battery_full) { 
      newStates.is_battery_full = true; 
      if (settings.battery_full) pushMessages.push("電池容量已滿"); 
    } else if (capacity <= 98 && oldStates.is_battery_full) { 
      newStates.is_battery_full = false;  
    } 

    if (capacity <= 20 && !oldStates.is_battery_low) { 
      newStates.is_battery_low = true; 
      if (settings.battery_low) pushMessages.push("電池電量過低 (<20%)"); 
    } else if (capacity >= 22 && oldStates.is_battery_low) { 
      newStates.is_battery_low = false; 
    } 

    if (linePowerDir === 0 && !oldStates.is_grid_off) { 
      newStates.is_grid_off = true; 
    } else if (linePowerDir === 1 && oldStates.is_grid_off) { 
      newStates.is_grid_off = false; 
    } 

    if (totalSolar <= 0 && !oldStates.is_no_pv) { 
      newStates.is_no_pv = true; 
      if (settings.no_pv) pushMessages.push("無太陽能發電"); 
    } else if (totalSolar > 20 && oldStates.is_no_pv) { 
      newStates.is_no_pv = false; 
    } 

    if (loadPercent >= 95 && loadPercent <= 100 && !oldStates.is_load_full) { 
      newStates.is_load_full = true; 
      if (settings.load_full) pushMessages.push("逆變器已達滿載 (>95%)"); 
    } else if (loadPercent < 85 && oldStates.is_load_full) { 
      newStates.is_load_full = false; 
    } 

    if (loadPercent > 100 && !oldStates.is_load_overload) { 
      newStates.is_load_overload = true; 
      if (settings.load_overload) pushMessages.push("逆變器已過載"); 
    } else if (loadPercent <= 95 && oldStates.is_load_overload) { 
      newStates.is_load_overload = false; 
    } 

    if (JSON.stringify(oldStates) !== JSON.stringify(newStates)) { 
      await supabaseAdmin.from('devices').update({ alert_states: newStates }).eq('id', device.id); 
        
      if (pushMessages.length > 0) { 
        const pushTitle = "⚠️ 儲能系統運行狀態";
        const pushBody = pushMessages.join('\n');

        // 🎯 新增 3：寫入歷史紀錄至 device_notifications
        await supabaseAdmin.from('device_notifications').insert({
          device_id: deviceId,
          title: pushTitle,
          message: pushBody
        });

        const { data: profile } = await supabaseAdmin.from('profiles').select('fcm_token').eq('id', device.user_id).single(); 
        if (profile?.fcm_token) { 
          try { 
            await getMessaging().send({ token: profile.fcm_token, notification: { title: pushTitle, body: pushBody } }); 
          } catch (fcmErr) { 
            console.error('❌ [FCM 發送失敗]:', fcmErr);  
          } 
        } 
      } 
    } 
    return new Response(JSON.stringify({ success: true }), { headers: { "Content-Type": "application/json" } }); 
  } catch (err) { 
    return new Response(String(err), { status: 500 }); 
  } 
})