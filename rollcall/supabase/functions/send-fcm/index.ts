import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import * as jose from "https://deno.land/x/jose@v4.14.4/index.ts"

serve(async (req) => {
  try {
    // Veritabanından gelen bildirim verisi
    const { record } = await req.json()
    
    // 1. Secret'tan Firebase bilgilerini al
    const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')
    
    // 2. Google Auth Token Oluşturma (FCM V1 API için)
    const jwt = await new jose.SignJWT({
      iss: serviceAccount.client_email,
      sub: serviceAccount.client_email,
      aud: "https://oauth2.googleapis.com/token",
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 3600,
      scope: "https://www.googleapis.com/auth/firebase.messaging"
    })
      .setProtectedHeader({ alg: 'RS256' })
      .sign(await jose.importPKCS8(serviceAccount.private_key, 'RS256'))

    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt
      })
    })
    const { access_token } = await tokenRes.json()

    // 3. Bildirimi Gönder (FCM V1 API)
    // Not: Buradaki '/topics/all' yerine öğrenciye özel token da kullanabilirsin
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${access_token}`
        },
        body: JSON.stringify({
          message: {
            topic: "all", // Şimdilik herkese gönderiyoruz test için
            notification: {
              title: record.message,
            }
          }
        })
      }
    )

    const result = await fcmRes.json()
    console.log("FCM Sonucu:", result)

    return new Response(JSON.stringify(result), { headers: { "Content-Type": "application/json" } })

  } catch (error) {
    console.error("Hata oluştu:", error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})
