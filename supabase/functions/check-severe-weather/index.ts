// deno-lint-ignore-file no-import-prefix no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'https://esm.sh/google-auth-library@9.14.0'

const CWA_API_KEY = Deno.env.get('CWA_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}';
const serviceAccount = JSON.parse(serviceAccountStr);

const SEVERE_WEATHER_KEYWORDS = ['雷', '颱風', '豪雨', '大豪雨', '超大豪雨', '大雨', '強降雨', '雷雨', '大雷雨', '陣雨'];

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
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // 擴充撈取欄位，加入 sn 供後續查詢遙測數據[cite: 2]
    const { data: devices, error } = await supabase
      .from('devices')
      .select(`
        id,
        sn,
        name, 
        address, 
        profiles!inner(fcm_token, backup_protection_enabled)
      `)
      .eq('profiles.backup_protection_enabled', true)
      .not('profiles.fcm_token', 'is', null);

    if (error) throw error;
    if (!devices || devices.length === 0) {
      return new Response(JSON.stringify({ message: "無符合條件的設備" }), { headers: { "Content-Type": "application/json" } });
    }

    const cityMap = new Map<string, any[]>();
    for (const device of devices) {
      const city = device.address.substring(0, 3).replace('台', '臺');
      if (!cityMap.has(city)) cityMap.set(city, []);
      cityMap.get(city)?.push(device);
    }

    const fcmAccessToken = await getFcmAccessToken();
    const projectId = serviceAccount.project_id;
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let pushCount = 0;

    for (const [city, cityDevices] of cityMap.entries()) {
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

      if (matchedKeyword) {
        for (const device of cityDevices) {
          // 查詢最新一筆電池 SOC 數據
          const { data: telemetry } = await supabase
            .from('telemetry_test')
            .select('battery_capacity')
            .eq('device_id', device.sn)
            .order('created_at', { ascending: false })
            .limit(1)
            .maybeSingle();

          const soc = telemetry?.battery_capacity ?? 0;
          
          // SOC 門檻邏輯判斷
          const adviceText = soc < 50 ? '，建議啟動惡劣天氣備援模式' : '';
          const notifyBody = `「${device.name}」所在區域，在未來3~6小時可能出現 ${matchedWxText}。目前電池容量為：${soc}%${adviceText}。`;

          const tokens = new Set<string>();
          if (device.profiles?.fcm_token) tokens.add(device.profiles.fcm_token);

          const { data: shares } = await supabase.from('device_shares')
            .select('shared_to_user_id')
            .eq('device_id', device.id)
            .eq('allow_notifications', true);

          if (shares && shares.length > 0) {
            const sharedUserIds = shares.map(s => s.shared_to_user_id).filter(Boolean);
            if (sharedUserIds.length > 0) {
              const { data: sharedProfiles } = await supabase.from('profiles').select('fcm_token').in('id', sharedUserIds);
              sharedProfiles?.forEach(p => { if (p.fcm_token) tokens.add(p.fcm_token); });
            }
          }

          for (const targetToken of Array.from(tokens)) {
            await fetch(fcmEndpoint, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${fcmAccessToken}` },
              body: JSON.stringify({
                message: {
                  token: targetToken,
                  notification: {
                    title: '⛈️ 惡劣天氣預警通知',
                    body: notifyBody
                  },
                  // 夾帶頁面跳轉所需的辨識資訊[cite: 2]
                  data: {
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                    route: "weather_forecast",
                    deviceDbId: device.id.toString()
                  }
                }
              })
            });
          }
          pushCount += tokens.size;
        }
      }
    }

    return new Response(JSON.stringify({ success: true, pushCount }), { headers: { "Content-Type": "application/json" } });
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
})