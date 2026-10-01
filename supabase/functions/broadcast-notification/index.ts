// deno-lint-ignore-file no-import-prefix
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { GoogleAuth } from "https://esm.sh/google-auth-library@9.0.0"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { title, body } = await req.json()

    if (!title || !body) {
      throw new Error('公告標題與內容不得為空')
    }

    // 🎯 1. 定義推播主題並印出初始 Log
    const targetTopic = 'system_broadcast'
    console.log(`🚀 [系統推播啟動] 準備發送廣播...`)
    console.log(`📌 [推播目標] 主題 (Topic): ${targetTopic}`)
    console.log(`📝 [推播內容] 標題: "${title}" | 內文: "${body}"`)

    const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountStr) {
      throw new Error('環境變數中缺少 Firebase 服務帳戶密鑰')
    }
    const serviceAccount = JSON.parse(serviceAccountStr)

    const auth = new GoogleAuth({
      credentials: {
        client_email: serviceAccount.client_email,
        private_key: serviceAccount.private_key,
      },
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })

    const client = await auth.getClient()
    const accessToken = await client.getAccessToken()

    const projectId = serviceAccount.project_id
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    const messagePayload = {
      message: {
        topic: targetTopic, // 帶入剛剛定義的變數
        notification: {
          title: title,
          body: body,
        },
        android: {
          priority: 'high',
          notification: { sound: 'default' }
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
      },
    }

    const fcmResponse = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(messagePayload),
    })

    const fcmData = await fcmResponse.json()

    if (!fcmResponse.ok) {
      console.error(`❌ [推播失敗] FCM 拒絕請求:`, fcmData)
      throw new Error(`FCM API 拒絕請求: ${JSON.stringify(fcmData)}`)
    }

    // 🎯 2. 印出成功 Log
    console.log(`✅ [推播成功] 訊息已成功交由 FCM 伺服器派發！`)

    return new Response(
      JSON.stringify({ success: true, message: '全域推播發送成功！', data: fcmData }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  } catch (error) {
    const err = error as Error;
    // 🎯 3. 印出系統層級錯誤 Log
    console.error(`💥 [系統錯誤] 執行推播函式時發生異常: ${err.message}`)
    
    return new Response(
      JSON.stringify({ success: false, message: err.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
    )
  }
})