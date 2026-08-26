// deno-lint-ignore-file no-import-prefix
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

// EMQX 連線資訊
const emqxHost = 'vb6a817a.ala.eu-central-1.emqxsl.com:8443'; 
const appId = 'b1880d1a'; 
const appSecret = 'EEEPjMbykFhK_8FP'; 

// 🎯 建立一個 Promise 延遲函式 (類似 Dart 的 Future.delayed)
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

serve(async (req: Request) => {
  try {
    // 🎯 現在我們預期收到的是一個名為 commands 的陣列
    const { sn, commands } = await req.json();

    // 驗證輸入參數
    if (!sn || !commands || !Array.isArray(commands)) {
      return new Response("Missing 'sn' or 'commands' array", { status: 400 });
    }

    const emqxApiUrl = `https://${emqxHost}/api/v5/publish`;
    const authHeader = 'Basic ' + btoa(`${appId}:${appSecret}`);
    const topic = `inverter/command/${sn}`;

    console.log(`🚀 準備批次下發 ${commands.length} 筆指令至設備 [${sn}]`);

    // 🎯 使用 for 迴圈依序處理每一條指令，並強迫排隊
    for (let i = 0; i < commands.length; i++) {
      const command = commands[i];
      const publishPayload = {
        topic: topic,
        payload: command,
        qos: 1
      };

      // 發送單一指令給 EMQX
      const response = await fetch(emqxApiUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': authHeader
        },
        body: JSON.stringify(publishPayload)
      });

      if (!response.ok) {
        throw new Error(`EMQX 拒絕指令 [${command}]，狀態碼: ${response.status}`);
      }

      console.log(`✅ [${i + 1}/${commands.length}] 成功發送: ${command}`);

      // 🎯 核心防護機制：如果這不是最後一條指令，就強制等待 1500 毫秒，再發下一條
      if (i < commands.length - 1) {
        await delay(1500); 
      }
    }

    // 所有指令皆發送完畢才回傳成功給 APP
    return new Response(JSON.stringify({ success: true, message: `Successfully sent ${commands.length} commands` }), { headers: { "Content-Type": "application/json" } });
  } catch (error) {
    console.error("❌ 批次指令發送失敗:", error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
})