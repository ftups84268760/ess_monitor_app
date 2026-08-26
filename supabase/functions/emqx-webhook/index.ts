// deno-lint-ignore-file no-import-prefix
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const payload = await req.json();
    
    // 🎯 修改 1：為了相容，同時抓取 device_id 或 dtu_sn（因為 Action 可能傳送這兩種 key）
    const { device_id, dtu_sn, ...telemetryData } = payload;
    const incomingId = device_id || dtu_sn;


    if (!incomingId) {
      console.error('錯誤：收到的資料缺少設備序號');
      return new Response('Bad Request: Missing device ID', { status: 400 });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const supabase = createClient(supabaseUrl, supabaseKey);

    // ==========================================
    // 驗證階段：確認這個逆變器 SN 是否存在於資料庫
    // ==========================================
    const { data: device, error: lookupError } = await supabase
      .from('devices')
      .select('sn')
      // 🎯 修改 2：用收到的序號，去比對資料庫真正的 `sn` 欄位 (不再是 dtu_sn 了！)
      .eq('sn', incomingId) 
      .single();

    if (lookupError || !device) {
      console.error(`驗證失敗：資料庫找不到 SN 為 ${incomingId} 的設備`, lookupError);
      return new Response('Not Found: Device not registered', { status: 404 });
    }

    // ==========================================
    // 寫入階段：將資料寫入 telemetry_test
    // ==========================================
    const { error: insertError } = await supabase
      .from('telemetry_test')
      .insert({
        device_id: device.sn,  // 填入驗證成功的逆變器 sn
        ...telemetryData       // 展開寫入電壓、電流等其餘數據
      });

    if (insertError) {
      console.error('寫入 telemetry_test 失敗:', insertError);
      return new Response('Internal Server Error: DB Insert Failed', { status: 500 });
    }

// ==========================================
    // 💓 狀態更新階段：寫入成功後，順便更新看門狗心跳
    // ==========================================
    const { error: heartbeatError } = await supabase
      .from('devices')
      .update({ 
        last_active_at: new Date().toISOString(),
        is_online: true 
      })
      .eq('sn', device.sn);

    if (heartbeatError) {
      // 這裡只印出警告，不 return Error，因為遙測數據已經成功存進去了
      console.warn(`⚠️ 設備 ${device.sn} 心跳更新失敗:`, heartbeatError); 
    }

    console.log(`✅ 成功處理設備 ${device.sn} 的遙測數據並更新心跳`);
    return new Response('Success', { status: 200 });

  } catch (err) {
    console.error('Webhook 執行期間發生未預期錯誤:', err);
    return new Response('Internal Server Error', { status: 500 });
  }
})