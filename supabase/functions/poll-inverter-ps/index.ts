// deno-lint-ignore no-import-prefix
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const supabase = createClient(supabaseUrl, supabaseServiceKey)
const delay = (ms: number) => new Promise(res => setTimeout(res, ms));

// EMQX 伺服器設定
const emqxHost = 'vb6a817a.ala.eu-central-1.emqxsl.com:8443'
const appId = Deno.env.get('EMQX_APP_ID') ?? 'b1880d1a'
const appSecret = Deno.env.get('EMQX_APP_SECRET') ?? 'EEEPjMbykFhK_8FP'

// 🚨 告警大腦：A-Z 字典對照表 (中英雙語對照)
const ALARM_DICTIONARY: Record<string, string> = {
  'A': 'Solar input 1 loss (Solar1 輸入電壓超出範圍)',
  'B': 'Solar input 2 loss (Solar2 輸入電壓超出範圍)',
  'C': 'Solar input 1 voltage too higher (Solar1 電壓過高)',
  'D': 'Solar input 2 voltage too higher (Solar2 電壓過高)',
  'E': 'Battery under (電池電壓過低)',
  'F': 'Battery low (電池電壓偏低)',
  'G': 'Battery open (電池未接)',
  'H': 'Battery voltage too higher (電池電压過高)',
  'I': 'Battery low in hybrid mode (混合模式電池電壓過低)',
  'J': 'Grid voltage high loss (市電輸入電壓過高)',
  'K': 'Grid voltage low loss (市電輸入電壓過低)',
  'L': 'Grid frequency high loss (市電輸入頻率過高)',
  'M': 'Grid frequency low loss (市電輸入頻率過低)',
  'N': 'AC input long-time avg voltage over (市電輸入平均電壓超標)',
  'O': 'AC input voltage loss (市電輸入電壓超出可用範圍)',
  'P': 'AC input frequency loss (市電頻率超出可用範圍)',
  'Q': 'AC input island (市電孤島效應)',
  'R': 'AC input phase dislocation (市電相序錯誤)',
  'S': 'Over temperature (設備過溫)',
  'T': 'Over load (負載過載)',
  'U': 'EPO active (緊急停機啟動)',
  'V': 'AC input wave loss (市電輸入波形異常)',
  'W': 'Equalization states (電池均充狀態)',
  'X': 'Rapid_OnOff states (外部觸發快速關機)',
  'Y': 'CT Parallel Error (CT 並聯設定錯誤)',
  'Z': 'FAN Lock Warning (風扇堵轉警告)'
};

Deno.serve(async (req: Request) => {
  try {
    const rawBodyText = await req.text()
    
    let body: Record<string, unknown> = {}
    try {
      // 過濾掉不可見字元，避免 JSON.parse 報錯
      // deno-lint-ignore no-control-regex
      const sanitizedText = rawBodyText.replace(/[\u0000-\u001F\u007F-\u009F]/g, "")
      body = JSON.parse(sanitizedText)
    } catch (_) {
      body = {}
    }

    const rawResponse = String(body.raw_response || body.payload || '')
    const deviceId = String(body.device_id || '01')
    const triggerSource = String(body.trigger || '')

    // ========================================================================
    // 情境 A1：收到遙測數據 (^D107) ➔ 寫入 telemetry_inv_ps
    // ========================================================================
    if (rawResponse.includes('^D107')) {
      console.log(`[Webhook Recv] 🎯 收到遙測數據: ${rawResponse.trim()}`)
      const parsedData = parseInverterPsResponse(rawResponse)
      
      const { data, error } = await supabase
        .from('telemetry_inv_ps')
        .insert({
          device_id: deviceId,
          raw_payload: rawResponse,
          ...parsedData
        })

      if (error) throw error

      // 💓 新增：寫入成功後，更新看門狗心跳與上線狀態
      await supabase.from('devices').update({
        last_active_at: new Date().toISOString(),
        is_online: true
      }).eq('sn', deviceId);

      return new Response(JSON.stringify({ success: true, inserted: data }), {
        headers: { "Content-Type": "application/json" }
      })
    }

    // ========================================================================
    // 情境 A2：收到綜合狀態數據 (^D119) ➔ 寫入 telemetry_test
    // ========================================================================
    if (rawResponse.includes('^D119')) {
      console.log(`[Webhook Recv] 📊 收到綜合狀態數據: ${rawResponse.trim()}`)
      const parsedGsData = parseInverterGsResponse(rawResponse)
      
      const { data, error } = await supabase
        .from('telemetry_test')
        .insert({
          device_id: deviceId,
          raw_payload: rawResponse,
          ...parsedGsData
        })

      if (error) throw error

      // 💓 新增：寫入成功後，更新看門狗心跳與上線狀態
      await supabase.from('devices').update({
        last_active_at: new Date().toISOString(),
        is_online: true
      }).eq('sn', deviceId);
      
      return new Response(JSON.stringify({ success: true, inserted: data }), {
        headers: { "Content-Type": "application/json" }
      })
    }

    // ========================================================================
    // 情境 A3：收到告警狀態 (^D054) ➔ Diff 比對演算法，寫入 device_alarms
    // ========================================================================
    if (rawResponse.includes('^D054')) {
      console.log(`[Webhook Recv] 🚨 收到告警狀態: ${rawResponse.trim()}`)
      
      // 清洗字串：擷取 ^D054 後面的部分，只保留數字與逗號
      const cleanStr = rawResponse.substring(rawResponse.indexOf('^D054') + 5).replace(/[^0-9,]/g, '');
      const parts = cleanStr.split(',');

      if (parts.length >= 26) {
        // 撈取資料庫中該設備「正在觸發中」的告警
        const { data: activeAlarms, error: fetchError } = await supabase
          .from('device_alarms')
          .select('id, alarm_code')
          .eq('device_id', deviceId)
          .eq('is_active', true);

        if (fetchError) throw fetchError;
        const activeAlarmCodes = (activeAlarms || []).map(a => a.alarm_code);
        const keys = Object.keys(ALARM_DICTIONARY); // A 到 Z

        // 逐一比對 26 碼狀態
        for (let i = 0; i < 26; i++) {
          const code = keys[i];
          const isTriggered = parts[i] === '1';
          const isCurrentlyActive = activeAlarmCodes.includes(code);

          if (isTriggered && !isCurrentlyActive) {
            // [觸發]：新增告警紀錄
            await supabase.from('device_alarms').insert({
              device_id: deviceId,
              alarm_code: code,
              alarm_message: ALARM_DICTIONARY[code],
              is_active: true
            });
            console.log(`[新增告警] 設備 ${deviceId}: ${ALARM_DICTIONARY[code]}`);
          } 
          else if (!isTriggered && isCurrentlyActive) {
            // [解除]：更新為已解除，寫入解除時間 (維持 UTC，由前端或 SQL 轉換本地時間)
            await supabase.from('device_alarms')
              .update({ is_active: false, resolved_at: new Date().toISOString() })
              .eq('device_id', deviceId)
              .eq('alarm_code', code)
              .eq('is_active', true);
            console.log(`[解除告警] 設備 ${deviceId}: ${ALARM_DICTIONARY[code]}`);
          }
        }
      }

      return new Response(JSON.stringify({ success: true, message: 'Alarms processed' }), { headers: { "Content-Type": "application/json" } })
    }

    // ========================================================================
    // 防護機制：非預期請求直接無視 (防迴圈)
    // ========================================================================
    if (rawResponse.includes('^P003') || (triggerSource !== 'cron' && !body.trigger)) {
      return new Response(JSON.stringify({ success: true, message: 'Ignored non-cron request' }), { headers: { "Content-Type": "application/json" } })
    }

    // ========================================================================
    // 情境 B：Cron 排程 ➔ 動態發送多道輪詢指令至所有設備
    // ========================================================================
    const cmdsToPublish = ['^P003PS\r', '^P003WS\r', '^P003GS\r']
    const emqxApiUrl = `https://${emqxHost}/api/v5/publish`
    const authHeader = 'Basic ' + btoa(`${appId}:${appSecret}`)

    console.log(`[Cron Triggered] ⏰ pg_cron 定時觸發：準備向所有上線設備下發輪詢指令群`)

    // 1. 查詢資料庫：找出所有已註冊且目前標記為上線的設備
    const { data: devices, error: dbError } = await supabase
      .from('devices')
      .select('sn') // 🎯 修正：從 dtu_sn 嚴格改回逆變器的 sn

    if (dbError) {
      console.error('❌ 查詢設備清單失敗:', dbError)
      throw new Error('無法撈取設備清單')
    }

    if (!devices || devices.length === 0) {
      console.log('⚠️ 目前沒有上線的設備需要輪詢')
      return new Response(JSON.stringify({ success: true, message: 'No online devices to poll' }), {
        headers: { "Content-Type": "application/json" }
      })
    }

    const publishPromises = devices.map(async (device) => {
      // 🎯 修正：防呆檢查改為 device.sn
      if (!device.sn) return { success: false, sn: 'unknown', reason: 'Missing sn' }
      
      // 🎯 修正：確保 Topic 綁定的是逆變器本體的序號
      const cmdTopic = `inverter/command/${device.sn}`
      let successCount = 0;
      let lastStatus = 200;

      try {
        for (const cmd of cmdsToPublish) {
          const apiResponse = await fetch(emqxApiUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': authHeader },
            body: JSON.stringify({ topic: cmdTopic, payload: cmd, qos: 0 })
          })

          if (apiResponse.ok) {
            successCount++;
          } else {
            lastStatus = apiResponse.status;
            console.error(`❌ [輪詢發送失敗] ${cmdTopic} 指令 ${cmd.trim()}, HTTP Status: ${lastStatus}`)
          }
          
          await delay(1000); 
        }

        if (successCount === cmdsToPublish.length) {
          console.log(`🎉 [輪詢成功] 已下發 PS, WS, GS 至 ${cmdTopic}`)
          return { success: true, sn: device.sn } // 🎯 修正回傳變數
        } else {
          return { success: false, sn: device.sn, status: lastStatus } // 🎯 修正回傳變數
        }
        
      } catch (err) {
        console.error(`❌ fetch EMQX API 失敗 (${cmdTopic}):`, err)
        return { success: false, sn: device.sn, error: String(err) } // 🎯 修正回傳變數
      }
    })

    const results = await Promise.all(publishPromises)
    const successful = results.filter(r => r.success).length
    const failed = results.length - successful

    return new Response(JSON.stringify({
      success: true,
      message: `Polling completed. Success: ${successful}, Failed: ${failed}`,
      details: results
    }), {
      headers: { "Content-Type": "application/json" }
    })

  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    })
  }
})

// ----------------------------------------------------------------------------
// 解析函式：處理遙測數據 (^D107)
// ----------------------------------------------------------------------------
function parseInverterPsResponse(resp: string) {
  const cleanStr = resp.trim(); 
  const parts = cleanStr.split(',');
  
  if (parts.length < 22) {
    throw new Error(`PS Response length mismatch. Expected 22 components, got ${parts.length}`);
  }

  const firstPart = parts[0].replace('^D107', '');

  return {
    solar1_input_power: parseFloat(firstPart) || 0,        // parts[0]
    solar2_input_power: parseFloat(parts[1]) || 0,         // parts[1]
    
    // ⚠️ 避開協議保留的連續空欄位陷阱 (,,)
    // 跳過 parts[2]

    ac_in_active_power_r: parseFloat(parts[3]) || 0,       // parts[3]
    ac_in_active_power_s: parseFloat(parts[4]) || 0,
    ac_in_active_power_t: parseFloat(parts[5]) || 0,
    ac_in_total_active_power: parseFloat(parts[6]) || 0,
    
    ac_out_active_power_r: parseFloat(parts[7]) || 0,
    ac_out_active_power_s: parseFloat(parts[8]) || 0,
    ac_out_active_power_t: parseFloat(parts[9]) || 0,
    ac_out_total_active_power: parseFloat(parts[10]) || 0,
    
    ac_out_apparent_power_r: parseFloat(parts[11]) || 0,
    ac_out_apparent_power_s: parseFloat(parts[12]) || 0,
    ac_out_apparent_power_t: parseFloat(parts[13]) || 0,
    ac_out_total_apparent_power: parseFloat(parts[14]) || 0,
    ac_out_power_percentage: parseFloat(parts[15]) || 0,
    
    ac_out_connect_status: parseInt(parts[16]) || 0,
    solar1_work_status: parseInt(parts[17]) || 0,
    solar2_work_status: parseInt(parts[18]) || 0,
    
    battery_power_direction: parseInt(parts[19]) || 0,
    dc_ac_power_direction: parseInt(parts[20]) || 0,
    
    line_power_direction: parseInt(parts[21].substring(0, 1)) || 0, 
  }
}

// ----------------------------------------------------------------------------
// 解析函式：處理綜合狀態數據 (^D119)
// ----------------------------------------------------------------------------
function parseInverterGsResponse(resp: string) {
  // 終極清洗：利用正規表達式，只保留標準 ASCII 字元，完美過濾結尾亂碼
  const cleanStr = resp.replace(/[^\x20-\x7E]/g, '').trim(); 
  const parts = cleanStr.split(',');

  // 防呆機制
  if (parts.length < 24) {
    throw new Error(`GS Response length mismatch. Got ${parts.length}`);
  }

  const firstPart = parts[0].replace('^D119', '');

  return {
    pv1_voltage: (parseFloat(firstPart) || 0) / 10.0,            // parts[0]
    pv2_voltage: (parseFloat(parts[1]) || 0) / 10.0,             // parts[1]
    pv1_current: (parseFloat(parts[2]) || 0) / 100.0,            // parts[2]
    pv2_current: (parseFloat(parts[3]) || 0) / 100.0,            // parts[3]
    
    battery_voltage: (parseFloat(parts[4]) || 0) / 10.0,         // parts[4]
    battery_capacity: parseInt(parts[5]) || 0,                   // parts[5]
    battery_current: (parseFloat(parts[6]) || 0) / 10.0,         // parts[6]
    
    ac_in_v_r: (parseFloat(parts[7]) || 0) / 10.0,               // parts[7]
    ac_in_v_s: (parseFloat(parts[8]) || 0) / 10.0,               // parts[8]
    ac_in_v_t: (parseFloat(parts[9]) || 0) / 10.0,               // parts[9]
    ac_in_freq: (parseFloat(parts[10]) || 0) / 100.0,            // parts[10]
    
    // 💡 協議在這裡保留了 parts[11], parts[12], parts[13] 作為空欄位
    
    ac_out_v_r: (parseFloat(parts[14]) || 0) / 10.0,             // parts[14]
    ac_out_v_s: (parseFloat(parts[15]) || 0) / 10.0,             // parts[15]
    ac_out_v_t: (parseFloat(parts[16]) || 0) / 10.0,             // parts[16]
    ac_out_freq: (parseFloat(parts[17]) || 0) / 100.0,           // parts[17]
    
    // ⚠️ 連續逗號陷阱區：parts[18], parts[19], parts[20] 是連續的逗號空欄位
    
    inner_temp: parseInt(parts[21]) || 0,                        // parts[21]
    comp_max_temp: parseInt(parts[22]) || 0,                     // parts[22]
    battery_temp: parseInt(parts[23]) || 0,                      // parts[23]
  }
}