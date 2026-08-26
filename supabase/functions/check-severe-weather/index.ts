// deno-lint-ignore-file no-import-prefix no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'https://esm.sh/google-auth-library@9.14.0'

const CWA_API_KEY = Deno.env.get('CWA_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// 讀取存入的 Firebase 服務帳戶 JSON
const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}';
const serviceAccount = JSON.parse(serviceAccountStr);

const SEVERE_WEATHER_KEYWORDS = ['雷', '颱風', '豪雨', '大豪雨', '超大豪雨', '大雨', '強降雨', '雷雨', '大雷雨', '陣雨'];

// 🎯 輔助函式：取得 FCM V1 API 專用的 Access Token
async function getFcmAccessToken() {
  const jwtClient = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const tokens = await jwtClient.authorize();
  return tokens.access_token;
}

serve(async (_req) => {
  try {
    console.log("🚀 [排程啟動] 開始執行惡劣天氣掃描...");

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 1. 撈取有開啟「惡劣天氣備援」且擁有 FCM Token 的使用者設備
    const { data: devices, error } = await supabase
      .from('devices')
      .select(`
        name, 
        address, 
        profiles!inner(fcm_token, backup_protection_enabled)
      `)
      .eq('profiles.backup_protection_enabled', true)
      .not('profiles.fcm_token', 'is', null);

    if (error) {
      console.error("❌ [資料庫錯誤] 撈取設備失敗:", error);
      throw error;
    }

    if (!devices || devices.length === 0) {
      console.log("⏸️ [略過] 目前沒有符合推播條件的設備，排程結束。");
      return new Response(JSON.stringify({ message: "無符合條件的設備" }), { headers: { "Content-Type": "application/json" } });
    }

    console.log(`✅ [資料撈取] 找到 ${devices.length} 台已開啟備援保護的設備，準備查詢氣象署 API...`);

    // 2. 將設備依「縣市」分組，避免重複呼叫氣象署 API
    const cityMap = new Map<string, any[]>();
    for (const device of devices) {
      const city = device.address.substring(0, 3).replace('台', '臺');
      if (!cityMap.has(city)) cityMap.set(city, []);
      cityMap.get(city)?.push(device);
    }

    // 取得 Firebase V1 Access Token 與專案 ID
    const fcmAccessToken = await getFcmAccessToken();
    const projectId = serviceAccount.project_id;
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let pushCount = 0; // 紀錄推播發送數量

    // 3. 遍歷每個城市查詢天氣並發送推播
    for (const [city, cityDevices] of cityMap.entries()) {
      console.log(`☁️ [氣象查詢] 正在查詢 ${city} 的天氣預報...`);
      
      const url = `https://opendata.cwa.gov.tw/api/v1/rest/datastore/F-C0032-001?Authorization=${CWA_API_KEY}&locationName=${encodeURIComponent(city)}`;
      const response = await fetch(url);
      const json = await response.json();
      
      const weatherElements = json.records?.location?.[0]?.weatherElement;
      if (!weatherElements) continue;

      const wxElement = weatherElements.find((e: any) => e.elementName === 'Wx');
      if (!wxElement) continue;

      let matchedKeyword = '';
      let matchedWxText = '';
      for (let i = 0; i < 2; i++) {
        const wxText = wxElement.time[i].parameter.parameterName;
        for (const kw of SEVERE_WEATHER_KEYWORDS) {
          if (wxText.includes(kw)) {
            matchedKeyword = kw;
            matchedWxText = wxText;
            break;
          }
        }
        if (matchedKeyword) break;
      }

      // 4. 若有惡劣天氣，使用 V1 架構觸發推播
      if (matchedKeyword) {
        console.log(`⚠️ [警報觸發] ${city} 預報出現「${matchedKeyword}」(${matchedWxText})，準備發送推播給 ${cityDevices.length} 台設備！`);
        
        for (const device of cityDevices) {
          const fcmToken = device.profiles.fcm_token;
          const notifyBody = `「${device.name}」預報未來3~6小時可能出現（${matchedWxText}），建議啟動惡劣天氣備援模式。`;

          // 使用 FCM V1 的專屬 JSON 格式發送推播
          await fetch(fcmEndpoint, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${fcmAccessToken}`
            },
            body: JSON.stringify({
              message: {
                token: fcmToken,
                notification: {
                  title: '⛈️ 惡劣天氣預警通知',
                  body: notifyBody
                }
              }
            })
          });
          
          pushCount++;
          console.log(`   👉 已發送推播給設備: ${device.name}`);
        }
      } else {
        console.log(`🌤️ [天氣良好] ${city} 未來 6 小時無惡劣天氣。`);
      }
    }

    console.log(`🎉 [排程結束] 本次總共發送了 ${pushCount} 則預警推播！`);
    return new Response(JSON.stringify({ success: true, message: "氣象掃描與 V1 推播完成" }), { headers: { "Content-Type": "application/json" } });
  } catch (error: any) {
    console.error("❌ [系統嚴重錯誤]:", error.message);
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
})