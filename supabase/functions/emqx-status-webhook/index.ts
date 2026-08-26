// deno-lint-ignore-file no-import-prefix
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const payload = await req.json();
    const { device_id, event } = payload;

    if (!device_id || !event) {
      console.error('錯誤：缺少 device_id 或 event 參數');
      return new Response('Bad Request', { status: 400 });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const supabase = createClient(supabaseUrl, supabaseKey);

    const isOnline = event === 'client.connected'; 

    if (isOnline) {
      // 🟢 設備上線：立刻更新狀態為 true，並刷新最後活躍時間
      const { error: updateError } = await supabase
        .from('devices')
        .update({ 
            is_online: true,
            last_active_at: new Date().toISOString() 
        })
        .eq('sn', device_id);

      if (updateError) throw updateError;
      console.log(`✅ 設備 ${device_id} 已重連，立刻標記為上線`);
      
    } else {
      // 🔴 設備斷線：【關鍵優化】不立刻標記為離線！
      // 面對 2 小時一次的 6 秒瞬間斷線，我們選擇「忽略立即更新 is_online = false」
      // 真正的離線判定，交給您的 watchdog-inverter-offline Cron Job 來處理
      console.log(`⚠️ 設備 ${device_id} 觸發斷線事件，進入寬限期，交由 Watchdog 進行最終判定`);
      
      // 💡 提示：如果您的 devices 表有 last_disconnected_at 欄位，可以記錄在這裡供日後分析，但不改動 is_online
    }
    
    return new Response('Success', { status: 200 });

  } catch (err) {
    console.error('Webhook 執行期間發生未預期錯誤:', err);
    return new Response('Internal Server Error', { status: 500 });
  }
})