/*
 * RollCall System - ESP32 Smart Attendance Controller
 * NİMBLE RAM OPTIMIZED & SSL BYPASS VERSION
 */

#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <NimBLEDevice.h> // STANDART BLE YERİNE NİMBLE KULLANIYORUZ
#include <WiFiClientSecure.h>
#include "time.h"

// --- AYARLAR ---
const char* ssid       = "Esp8266";          
const char* password   = "esp8266.";      

const char* supabaseHost = "vytqqwrcmmjuutysxwxl.supabase.co";
const char* supabaseKey  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ5dHFxd3JjbW1qdXV0eXN4d3hsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTg2ODEsImV4cCI6MjA4OTgzNDY4MX0.aRPGwB93MYCam9gxC_08FDeKY6MQdwui9Mq94PSnFcQ"; 
const char* classroomId  = "7023ba8c-6535-4185-bf45-c04a8aae8a7e";

const char* ntpServer     = "pool.ntp.org";
const long  gmtOffset_sec = 10800;           

#define SCAN_DURATION  5                      

// Global Değişkenler
bool isAttendanceActive = false;
unsigned long lastStatusCheck = 0;
unsigned long lastScanTime = 0;
String currentCourseId = "";

struct FoundStudent {
  uint16_t schoolNo;
  int rssi;
  bool recorded;
};

const int MAX_STUDENTS = 50;
FoundStudent foundStudents[MAX_STUDENTS];
int studentCount = 0;

NimBLEScan* pBLEScan;
WiFiClientSecure client;

// --- FONKSİYONLAR ---

void markStudentPresent(uint16_t schoolNo) {
  if (WiFi.status() != WL_CONNECTED) return;
  
  HTTPClient http;
  client.setInsecure(); 
  client.setTimeout(15000); 

  String url = "https://" + String(supabaseHost) + "/rest/v1/rpc/mark_present_by_school_no";
  
  if (http.begin(client, url)) {
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    http.addHeader("Content-Type", "application/json");
    http.addHeader("User-Agent", "Mozilla/5.0 (ESP32; Mobile)"); 
    
    String jsonBody = "{\"p_school_no\": \"" + String(schoolNo) + "\", \"p_course_id\": \"" + currentCourseId + "\"}";
    
    int httpCode = http.POST(jsonBody);
    if (httpCode > 0) {
      Serial.printf("  [KAYIT] Okul No %u -> HTTP: %d\n", schoolNo, httpCode);
      if (httpCode == 200 || httpCode == 204) {
         for (int i = 0; i < studentCount; i++) {
           if (foundStudents[i].schoolNo == schoolNo) foundStudents[i].recorded = true;
         }
      }
    } else {
      Serial.printf("  [KAYIT HATA] %s\n", http.errorToString(httpCode).c_str());
    }
    http.end();
  }
}

void checkAttendanceStatus() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  client.setInsecure();
  client.setTimeout(10000); 

  String url = "https://" + String(supabaseHost) + "/rest/v1/classrooms?select=is_automation_on,is_automation_on&id=eq." + String(classroomId);
  
  if (http.begin(client, url)) {
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    http.addHeader("User-Agent", "Mozilla/5.0 (ESP32; Mobile)"); 
    
    int httpCode = http.GET();
    if (httpCode == 200) {
      String payload = http.getString();
      bool newStatus = payload.indexOf("\"is_automation_on\":true") != -1;
      
      if (newStatus && !isAttendanceActive) {
        Serial.println("\n>>> [SİSTEM] Yoklama Başlatıldı!");
        isAttendanceActive = true;
        studentCount = 0;
      } else if (!newStatus && isAttendanceActive) {
        Serial.println("\n>>> [SİSTEM] Yoklama Durduruldu!");
        isAttendanceActive = false;
      }
      
      int idx = payload.indexOf("\"is_automation_on\":\"");
      if (idx != -1) {
        int start = idx + 20;
        int end = payload.indexOf("\"", start);
        currentCourseId = payload.substring(start, end);
      }
    } else {
      Serial.printf(">>> [HATA] HTTP Kod: %d | Detay: %s\n", httpCode, http.errorToString(httpCode).c_str());
      if (httpCode == -1) client.stop();
    }
    http.end();
  }
}

// --- NİMBLE CALLBACK (BELLEK DOSTU TARAMA) ---
class MyCallbacks: public NimBLEScanCallbacks {    
  void onResult(NimBLEAdvertisedDevice* dev) {
      if (dev->haveManufacturerData()) {
        std::string data = dev->getManufacturerData();
        
        // Apple iBeacon (0x4C) kontrolü
        if (data.length() >= 25 && (uint8_t)data[0] == 0x4C) {
          // Öğrenci Okul No (Minor) değeri verinin 22. ve 23. byte'larında saklıdır
          uint16_t minor = ((uint8_t)data[22] << 8) | (uint8_t)data[23];
          
          bool exists = false;
          for(int i=0; i<studentCount; i++) {
            if(foundStudents[i].schoolNo == minor) {
              exists = true; 
              break;
            }
          }
          
          if(!exists && studentCount < MAX_STUDENTS) {
            foundStudents[studentCount] = {minor, dev->getRSSI(), false};
            studentCount++;
            Serial.printf("  + Cihaz Algılandı: %u (RSSI: %d)\n", minor, dev->getRSSI());
          }
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  delay(1000);

  WiFi.begin(ssid, password);
  Serial.print("WiFi'ya bağlanılıyor");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n✓ WiFi Bağlandı.");

  configTime(gmtOffset_sec, 0, ntpServer);
  struct tm timeinfo;
  if(!getLocalTime(&timeinfo)){
    Serial.println("Saati alma başarısız!");
  } else {
    Serial.println("✓ Saat Senkronize Edildi.");
  }

  // RAM DOSTU NİMBLE BAŞLATILIYOR
  NimBLEDevice::init("RollCall_Hardware");
  pBLEScan = NimBLEDevice::getScan();
  pBLEScan->setScanCallbacks(new MyCallbacks());
  pBLEScan->setActiveScan(true);
  pBLEScan->setInterval(100);
  pBLEScan->setWindow(99);

  Serial.println(">>> Sistem Hazır, Supabase dinleniyor...");
}

void loop() {
  if (millis() - lastStatusCheck > 3000) {
    lastStatusCheck = millis();
    checkAttendanceStatus();
  }
  
  if (isAttendanceActive && (millis() - lastScanTime > 10000)) {
    lastScanTime = millis();
    Serial.println("\n>>> BLE Taraması Başlatılıyor...");
    pBLEScan->start(SCAN_DURATION, false);
    
    for(int i=0; i<studentCount; i++) {
      if(!foundStudents[i].recorded) {
        markStudentPresent(foundStudents[i].schoolNo);
        delay(200); 
      }
    }
    pBLEScan->clearResults();
    Serial.println(">>> Tarama ve Kayıt Döngüsü Tamamlandı.");
  }
  delay(10);
}