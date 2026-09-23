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
  'H': 'Battery voltage too higher (電池電壓過高)',
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

// 💥 系統錯誤大腦：合併產品A與產品B的 01-89 字典對照表
const FAULT_DICTIONARY: Record<string, string> = {
  '01': 'BUS exceed the upper limit (BUS電壓過高)',
  '02': 'BUS drop to the lower limit (BUS電壓過低)',
  '03': 'BUS soft start time out (BUS軟啟動超時)',
  '04': 'Inverter voltage soft start time out (逆變器軟啟動超時)',
  '05': 'Inverter current exceed the upper limit (逆變器電流過載)',
  '06': 'Temperature over (溫度過高)',
  '07': 'Inverter relay work abnormal (逆變器繼電器異常)',
  '08': 'Current sample abnormal when inverter doesn\'t work (非工作時電流採樣異常)',
  '09': 'Solar input voltage exceed upper limit (太陽能輸入電壓過高)',
  '10': 'SPS / Solar power voltage abnormal (輔助電源或太陽能電壓異常)',
  '11': 'Solar input current exceed upper limit (Solar輸入電流過大)',
  '12': 'Leakage current exceed normal range (漏電流超過正常範圍)',
  '13': 'Solar insulation resistance too low (Solar對地絕緣阻抗過低)',
  '14': 'Inverter DC current exceed permit range (併網時逆變直流分量超限)',
  '15': 'AC input diff between master and slave CPU (主從CPU對AC輸入偵測差異過大)',
  '16': 'Leakage current detect circuit abnormal (非工作時漏電流偵測電路異常)',
  '17': 'Communication loss between master and slave CPU (主從CPU通訊遺失)',
  '18': 'Communicate data un-match between master and slave CPU (主從CPU通訊資料不匹配)',
  '19': 'Main Board CT Fault / AC input ground wire loss (主機板CT故障 / 市電地線未接)', 
  '21': 'Grid Board CT Fault (電網板CT故障)',
  '22': 'Battery voltage exceed upper limit (電池電壓過高)',
  '23': 'Over load (負載過載)',
  '24': 'S phase Inverter current exceed the upper limit (S相逆變過流)',
  '25': 'T phase Inverter current exceed the upper limit (T相逆變過流)',
  '26': 'AC output short (輸出短路)',
  '27': 'Fan lock (風扇堵轉)',
  '29': 'Inverter Current sample abnormal when inverter doesn\'t work (非工作時逆變電流採樣異常)',
  '30': 'S phase Inverter DC current exceed permit range (併網時S相逆變直流分量超過允許範圍)',
  '31': 'T phase Inverter DC current exceed permit range (併網時T相逆變直流分量超過允許範圍)',
  '32': 'Battery DC-DC current over (電池DC-DC過電流)',
  '33': 'AC output voltage too low (AC輸出電壓過低)',
  '34': 'AC output voltage too high (AC輸出電壓過高)',
  '35': 'Control board wiring error (控制板接線錯誤)',
  '36': 'AC circuit voltage sample error (AC電路電壓採樣異常)',
  '37': 'AC N wire current over (市電N線過流)',
  '39': 'S phase AC output voltage too low (S相輸出電壓過低)',
  '40': 'T phase AC output voltage too low (T相輸出電壓過低)',
  '41': 'S phase AC output voltage too high (S相輸出電壓過高)',
  '42': 'T phase AC output voltage too high (T相輸出電壓過高)',
  '50': 'Negative power detected / Relay version error (偵測到逆向功率 / 繼電器版本錯誤)',
  '60': 'Negative power detected (偵測到反向功率)',
  '61': 'Driver signal lost from relay board (Relay board驅動訊號遺失)',
  '62': 'Communication lost between main-board and relay-board (主機與繼電器板通訊遺失)',
  '63': 'Versions are different between main board and relay board (主板與relay board版本不相容)',
  '71': 'Parallel version is incompatible (並聯版本不相容)',
  '72': 'CT current detection abnormal (電流偵測異常)',
  '73': 'CAN fault (CAN通訊錯誤)',
  '74': 'HOST lost (主機通訊遺失)',
  '75': 'SYN lost (同步失敗)',
  '79': 'BUS Unbalanced (BUS電壓不平衡)',
  '80': 'BUS Balances circuit fault / CAN lost (BUS平衡硬體故障 / CAN丟失)',
  '81': 'HOST lost (主機遺失)',
  '82': 'SYN lost (同步遺失)',
  '89': 'BUS Balances overcurrent (BUS平衡過流)'
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

      // 💓 寫入成功後，更新看門狗心跳與上線狀態
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

      // 💓 寫入成功後，更新看門狗心跳與上線狀態
      await supabase.from('devices').update({
        last_active_at: new Date().toISOString(),
        is_online: true
      }).eq('sn', deviceId);
      
      return new Response(JSON.stringify({ success: true, inserted: data }), {
        headers: { "Content-Type": "application/json" }
      })
    }

    // ========================================================================
    // 情境 A3：收到告警狀態 (^D054 或 ^D050) ➔ Diff 比對演算法，寫入 device_alarms
    // ========================================================================
    const wsMatch = rawResponse.match(/\^D(054|050)/);
    if (wsMatch) {
      const header = wsMatch[0];
      console.log(`[Webhook Recv] 🚨 收到告警狀態: ${rawResponse.trim()}`)
  
      // 清洗字串：擷取表頭後面的部分，只保留數字與逗號
      const cleanStr = rawResponse.substring(rawResponse.indexOf(header) + 5).replace(/[^0-9,]/g, '');
      const parts = cleanStr.split(',');

      // 🎯 修改：降低長度限制至 24，以兼容產品 B (^D050)
      if (parts.length >= 24) {
        const { data: activeAlarms, error: fetchError } = await supabase
          .from('device_alarms')
          .select('id, alarm_code')
          .eq('device_id', deviceId)
          .eq('is_active', true);

        if (fetchError) throw fetchError;
        const activeAlarmCodes = (activeAlarms || []).map(a => a.alarm_code);
        const keys = Object.keys(ALARM_DICTIONARY); // A 到 Z

        // 🎯 修改：取陣列長度與 26 的最小值，避免產品 B 取到 undefined
       const checkLength = Math.min(parts.length, 26);
    
        // 逐一比對狀態
        for (let i = 0; i < checkLength; i++) {
          const code = keys[i];
          const isTriggered = parts[i] === '1';
          const isCurrentlyActive = activeAlarmCodes.includes(code);

          if (isTriggered && !isCurrentlyActive) {
            await supabase.from('device_alarms').insert({
              device_id: deviceId, alarm_code: code, alarm_message: ALARM_DICTIONARY[code], is_active: true
            });
            console.log(`[新增告警] 設備 ${deviceId}: ${ALARM_DICTIONARY[code]}`);
          } 
          else if (!isTriggered && isCurrentlyActive) {
            await supabase.from('device_alarms')
              .update({ is_active: false, resolved_at: new Date().toISOString() })
              .eq('device_id', deviceId).eq('alarm_code', code).eq('is_active', true);
            console.log(`[解除告警] 設備 ${deviceId}: ${ALARM_DICTIONARY[code]}`);
          }
        }
      }

      return new Response(JSON.stringify({ success: true, message: 'Alarms processed' }), { headers: { "Content-Type": "application/json" } })
    }

   // ========================================================================
   // 情境 A4：收到系統錯誤狀態 (^D008) ➔ 寫入 device_alarms
   // ========================================================================
   if (rawResponse.includes('^D008')) {
     console.log(`[Webhook Recv] 💥 收到系統錯誤狀態: ${rawResponse.trim()}`)
  
     // 🎯 核心修復：使用正規表達式精準抓取逗號前後的兩組數字/字元
     // \^D008 尋找開頭
     // ([A-Za-z0-9]+) 抓取第一組 AA
     // , 尋找分隔逗號
     // ([A-Za-z0-9]+) 抓取第二組 BB
     const match = rawResponse.match(/\^D008([A-Za-z0-9]+),([A-Za-z0-9]+)/);
  
     if (match && match.length >= 3) { 
       // match[1] 是 AA (最新故障代碼)
       // match[2] 是 BB (Flash中儲存的ID)
       const aaRaw = match[1];
       const bbFlash = match[2];
    
       // 取得 AA 並確保它是兩位數字串 (例如 '1' -> '01', '0' -> '00')
       const latestFaultCode = aaRaw.padStart(2, '0'); 
    
       console.log(`[解析結果] 最新錯誤 (AA): ${latestFaultCode}, Flash記錄 (BB): ${bbFlash}`);

       // 撈取資料庫中該設備「正在觸發中」的錯誤紀錄
       const { data: activeFaults, error: fetchError } = await supabase
         .from('device_alarms')
         .select('id, alarm_code')
         .eq('device_id', deviceId)
         .eq('is_active', true);

       if (fetchError) throw fetchError;
       const activeFaultCodes = (activeFaults || []).map(a => a.alarm_code);

       if (latestFaultCode === '00') {
         // [全部解除]：回傳 00 代表目前沒有系統錯誤，把所有數字錯誤碼標記為已解決
         for (const code of activeFaultCodes) {
           // 只解除數字碼 (保留 A-Z 告警)
           if (code.match(/^[0-9]+$/)) {
             await supabase.from('device_alarms')
               .update({ is_active: false, resolved_at: new Date().toISOString() })
               .eq('device_id', deviceId)
               .eq('alarm_code', code)
               .eq('is_active', true);
             console.log(`[解除錯誤] 設備 ${deviceId}: Code ${code}`);
           }
         }
       } else {
         // [觸發]：有收到具體的錯誤碼
         if (!activeFaultCodes.includes(latestFaultCode)) {
           const errorMsg = FAULT_DICTIONARY[latestFaultCode] || `System Fault ${latestFaultCode} (未定義錯誤)`;
           await supabase.from('device_alarms').insert({
             device_id: deviceId,
             alarm_code: latestFaultCode,
             alarm_message: errorMsg,
             is_active: true
           });
           console.log(`[新增錯誤] 設備 ${deviceId}: ${errorMsg}`);
         } 
      
         // [自動解除舊錯誤]：因為協議只給「最新」的一個錯誤，把其他的數字錯誤標記為解除
         for (const code of activeFaultCodes) {
           if (code.match(/^[0-9]+$/) && code !== latestFaultCode) {
             await supabase.from('device_alarms')
               .update({ is_active: false, resolved_at: new Date().toISOString() })
               .eq('device_id', deviceId)
               .eq('alarm_code', code)
               .eq('is_active', true);
             console.log(`[解除舊錯誤] 設備 ${deviceId}: Code ${code}`);
           }
         }
       }
     } else {
        console.log(`[警告] ^D008 格式不符，無法解析: ${rawResponse}`);
     }

     return new Response(JSON.stringify({ success: true, message: 'Faults processed' }), { headers: { "Content-Type": "application/json" } })
    }

    // ========================================================================
    // 防護機制：非預期請求直接無視 (防迴圈)
    // ========================================================================
    if (rawResponse.includes('^P003') || rawResponse.includes('^P004') || (triggerSource !== 'cron' && !body.trigger)) {
      return new Response(JSON.stringify({ success: true, message: 'Ignored non-cron request' }), { headers: { "Content-Type": "application/json" } })
    }

    // ========================================================================
    // 情境 B：Cron 排程 ➔ 動態發送多道輪詢指令至所有設備
    // ========================================================================
    // 🎯 新增了 ^P004CFS\r 查詢系統錯誤狀態
    const cmdsToPublish = ['^P003PS\r', '^P003WS\r', '^P003GS\r', '^P004CFS\r']
    const emqxApiUrl = `https://${emqxHost}/api/v5/publish`
    const authHeader = 'Basic ' + btoa(`${appId}:${appSecret}`)

    console.log(`[Cron Triggered] ⏰ pg_cron 定時觸發：準備向所有上線設備下發輪詢指令群`)

    // 1. 查詢資料庫：找出所有已註冊的設備
    const { data: devices, error: dbError } = await supabase
      .from('devices')
      .select('sn') 

    if (dbError) {
      console.error('❌ 查詢設備清單失敗:', dbError)
      throw new Error('無法撈取設備清單')
    }

    if (!devices || devices.length === 0) {
      console.log('⚠️ 目前沒有註冊的設備需要輪詢')
      return new Response(JSON.stringify({ success: true, message: 'No online devices to poll' }), {
        headers: { "Content-Type": "application/json" }
      })
    }

    const publishPromises = devices.map(async (device) => {
      if (!device.sn) return { success: false, sn: 'unknown', reason: 'Missing sn' }
      
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
          console.log(`🎉 [輪詢成功] 已下發 PS, WS, GS, CFS 至 ${cmdTopic}`)
          return { success: true, sn: device.sn } 
        } else {
          return { success: false, sn: device.sn, status: lastStatus } 
        }
        
      } catch (err) {
        console.error(`❌ fetch EMQX API 失敗 (${cmdTopic}):`, err)
        return { success: false, sn: device.sn, error: String(err) } 
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
    solar1_input_power: parseFloat(firstPart) || 0,
    solar2_input_power: parseFloat(parts[1]) || 0,
    
    // 跳過 parts[2]

    ac_in_active_power_r: parseFloat(parts[3]) || 0,
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
    pv1_voltage: (parseFloat(firstPart) || 0) / 10.0,
    pv2_voltage: (parseFloat(parts[1]) || 0) / 10.0,
    pv1_current: (parseFloat(parts[2]) || 0) / 100.0,
    pv2_current: (parseFloat(parts[3]) || 0) / 100.0,
    
    battery_voltage: (parseFloat(parts[4]) || 0) / 10.0,
    battery_capacity: parseInt(parts[5]) || 0,
    battery_current: (parseFloat(parts[6]) || 0) / 10.0,
    
    ac_in_v_r: (parseFloat(parts[7]) || 0) / 10.0,
    ac_in_v_s: (parseFloat(parts[8]) || 0) / 10.0,
    ac_in_v_t: (parseFloat(parts[9]) || 0) / 10.0,
    ac_in_freq: (parseFloat(parts[10]) || 0) / 100.0,
    
    // parts[11], parts[12], parts[13] 保留空欄位
    
    ac_out_v_r: (parseFloat(parts[14]) || 0) / 10.0,
    ac_out_v_s: (parseFloat(parts[15]) || 0) / 10.0,
    ac_out_v_t: (parseFloat(parts[16]) || 0) / 10.0,
    ac_out_freq: (parseFloat(parts[17]) || 0) / 100.0,
    
    // parts[18], parts[19], parts[20] 連續空欄位
    
    inner_temp: parseInt(parts[21]) || 0,
    comp_max_temp: parseInt(parts[22]) || 0,
    battery_temp: parseInt(parts[23]) || 0,
  }
}