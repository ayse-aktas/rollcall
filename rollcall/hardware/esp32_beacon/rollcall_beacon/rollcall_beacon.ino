/*
 * RollCall System - ESP32 Smart Attendance Controller
 * v2.1 - Hash-Based | Standard BLE | Supabase
 */

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEScan.h>
#include <BLEAdvertisedDevice.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include "time.h"
#include "esp_bt.h"

// --- AYARLAR ---
const char* ssid       = "Esp8266";          
const char* password   = "esp8266.";      

const char* supabaseHost = "vytqqwrcmmjuutysxwxl.supabase.co";
const char* supabaseKey  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ5dHFxd3JjbW1qdXV0eXN4d3hsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTg2ODEsImV4cCI6MjA4OTgzNDY4MX0.aRPGwB93MYCam9gxC_08FDeKY6MQdwui9Mq94PSnFcQ"; 
const char* classroomId  = "7023ba8c-6535-4185-bf45-c04a8aae8a7e";

const char* ntpServer     = "pool.ntp.org";
const long  gmtOffset_sec = 10800;           

#define SCAN_DURATION  10
#define MIN_RSSI       -85  // Bu degerden zayif sinyalleri yoksay

// RollCall UUID: E2C56DB5-DFFB-48D2-B060-D0F5A71096B1
const uint8_t ROLLCALL_UUID[] = {
  0xE2, 0xC5, 0x6D, 0xB5, 0xDF, 0xFB, 0x48, 0xD2,
  0xB0, 0x60, 0xD0, 0xF5, 0xA7, 0x10, 0x96, 0xB1
};

// Global Degiskenler
bool isAttendanceActive = false;
unsigned long lastStatusCheck = 0;
unsigned long lastScanTime = 0;
String currentCourseId = "";

struct FoundStudent {
  char hashStr[9];  // "74DF1CBD" formatinda
  int rssi;
  bool recorded;
};

const int MAX_STUDENTS = 50;
FoundStudent foundStudents[MAX_STUDENTS];
int studentCount = 0;

BLEScan* pBLEScan;
WiFiClientSecure client;  // Global - RAM tasarrufu

// --- UUID KONTROL FONKSIYONU (CALISAN KOD) ---
bool checkBeaconUUID(BLEAdvertisedDevice& device, uint16_t& outMajor, uint16_t& outMinor) {
  if (!device.haveManufacturerData()) return false;
  
  String mfData = device.getManufacturerData();
  if (mfData.length() < 24) return false;
  
  const uint8_t* data = (const uint8_t*)mfData.c_str();
  int uuidOffset = -1;
  
  // Format 1: iBeacon (Apple) -> bytes[2]=0x02, bytes[3]=0x15
  if (mfData.length() >= 25 && data[2] == 0x02 && data[3] == 0x15) {
    uuidOffset = 4;
  }
  // Format 2: AltBeacon (Android) -> bytes[2]=0xBE, bytes[3]=0xAC
  else if (mfData.length() >= 24 && data[2] == 0xBE && data[3] == 0xAC) {
    uuidOffset = 4;
  }
  
  if (uuidOffset < 0) return false;
  
  // UUID karsilastir (16 byte)
  for (int i = 0; i < 16; i++) {
    if (data[uuidOffset + i] != ROLLCALL_UUID[i]) return false;
  }
  
  // Major ve Minor oku (Big Endian)
  outMajor = (data[uuidOffset + 16] << 8) | data[uuidOffset + 17];
  outMinor = (data[uuidOffset + 18] << 8) | data[uuidOffset + 19];
  
  return true;
}

// --- BLE CALLBACK ---
class MyAdvertisedDeviceCallbacks: public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) {
    uint16_t major = 0, minor = 0;
    
    if (checkBeaconUUID(advertisedDevice, major, minor)) {
      // Hash string olustur: Major+Minor = "74DF1CBD"
      char hexBuf[9];
      sprintf(hexBuf, "%04X%04X", major, minor);
      
      // Tekrar eklememek icin kontrol
      bool exists = false;
      for (int i = 0; i < studentCount; i++) {
        if (strcmp(foundStudents[i].hashStr, hexBuf) == 0) {
          exists = true;
          break;
        }
      }
      
      if (!exists && studentCount < MAX_STUDENTS) {
        int rssi = advertisedDevice.getRSSI();
        if (rssi < MIN_RSSI) {
          Serial.printf("  ~ Zayif sinyal, yoksayildi: %s (RSSI: %d)\n", hexBuf, rssi);
          return;
        }
        strcpy(foundStudents[studentCount].hashStr, hexBuf);
        foundStudents[studentCount].rssi = rssi;
        foundStudents[studentCount].recorded = false;
        studentCount++;
        Serial.printf("  + Ogrenci Bulundu! Hash: %s (RSSI: %d)\n", hexBuf, rssi);
      }
    }
  }
};

// --- SUPABASE: Hash ile yoklama kaydet ---
void markStudentPresent(const char* hashStr) {
  if (WiFi.status() != WL_CONNECTED) return;
  
  HTTPClient http;
  client.setInsecure(); 
  client.setTimeout(15000); 

  String url = "https://" + String(supabaseHost) + "/rest/v1/rpc/mark_attendance_by_hash";
  
  if (http.begin(client, url)) {
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    http.addHeader("Content-Type", "application/json");
    http.addHeader("User-Agent", "Mozilla/5.0 (ESP32; Mobile)"); 
    
    String jsonBody = "{\"p_beacon_hash\": \"" + String(hashStr) + "\", \"p_course_id\": \"" + currentCourseId + "\"}";
    
    int httpCode = http.POST(jsonBody);
    if (httpCode > 0) {
      String response = http.getString();
      Serial.printf("  [KAYIT] Hash %s -> HTTP: %d | %s\n", hashStr, httpCode, response.c_str());
      if (httpCode == 200 || httpCode == 204) {
         for (int i = 0; i < studentCount; i++) {
           if (strcmp(foundStudents[i].hashStr, hashStr) == 0) foundStudents[i].recorded = true;
         }
      }
    } else {
      Serial.printf("  [KAYIT HATA] %s\n", http.errorToString(httpCode).c_str());
    }
    http.end();
  }
}

// --- SUPABASE: Otomasyon durumu kontrol ---
void checkAttendanceStatus() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  client.setInsecure();
  client.setTimeout(10000); 

  String url = "https://" + String(supabaseHost) + "/rest/v1/classrooms?select=is_automation_on,active_course_id&id=eq." + String(classroomId);
  
  if (http.begin(client, url)) {
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    http.addHeader("User-Agent", "Mozilla/5.0 (ESP32; Mobile)"); 
    
    int httpCode = http.GET();
    if (httpCode == 200) {
      String payload = http.getString();
      bool newStatus = payload.indexOf("\"is_automation_on\":true") != -1;
      
      if (newStatus && !isAttendanceActive) {
        Serial.println("\n>>> [SISTEM] Yoklama Baslatildi!");
        isAttendanceActive = true;
        studentCount = 0;
        
        // active_course_id'yi parse et
        int idx = payload.indexOf("\"active_course_id\":\"");
        if (idx != -1) {
          int start = idx + 20;
          int end = payload.indexOf("\"", start);
          if (end > start) {
            currentCourseId = payload.substring(start, end);
            Serial.print("   Ders ID: ");
            Serial.println(currentCourseId);
          }
        }
      } else if (!newStatus && isAttendanceActive) {
        Serial.println("\n>>> [SISTEM] Yoklama Durduruldu!");
        isAttendanceActive = false;
        currentCourseId = "";
      }
    } else {
      Serial.printf(">>> [HATA] HTTP Kod: %d | Detay: %s\n", httpCode, http.errorToString(httpCode).c_str());
      if (httpCode == -1) client.stop();
    }
    http.end();
  }
}

// --- SETUP ---
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n====================================");
  Serial.println("  RollCall Akilli Yoklama v2.1");
  Serial.println("  Hash-Based | BLE | Supabase");
  Serial.println("====================================\n");

  // Classic BT bellegini serbest birak (RAM tasarrufu - HTTPS icin gerekli)
  esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT);

  WiFi.begin(ssid, password);
  WiFi.setSleep(false); // WiFi uyku modunu kapat
  Serial.print("WiFi'ya baglaniyor");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n✓ WiFi Baglandi.");
  Serial.print("   IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("   Free RAM: ");
  Serial.println(ESP.getFreeHeap());

  configTime(gmtOffset_sec, 0, ntpServer);
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) {
    Serial.println("Saati alma basarisiz!");
  } else {
    Serial.println("✓ Saat Senkronize Edildi.");
  }

  // SSL sertifika dogrulamasi atla
  client.setInsecure();

  Serial.println(">>> Sistem Hazir, Supabase dinleniyor...\n");
}

// --- BLE BASLAT / DURDUR (RAM yonetimi) ---
void startBLE() {
  BLEDevice::init("");
  pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(new MyAdvertisedDeviceCallbacks());
  pBLEScan->setActiveScan(true);
  pBLEScan->setInterval(100);
  pBLEScan->setWindow(99);
}

void stopBLE() {
  pBLEScan->stop();
  pBLEScan->clearResults();
  BLEDevice::deinit(false);
  delay(100);
}

// --- LOOP ---
void loop() {
  // BLE kapali - HTTP icin yeterli RAM var
  // Her 2 saniyede otomasyon durumunu kontrol et
  if (millis() - lastStatusCheck > 2000) {
    lastStatusCheck = millis();
    checkAttendanceStatus();
  }
  
  // Otomasyon aktifse: BLE ac -> tara -> BLE kapat -> HTTP gonder
  if (isAttendanceActive && (millis() - lastScanTime > 12000)) {
    lastScanTime = millis();
    
    // ADIM 1: BLE baslat ve tara
    Serial.println("\n>>> BLE Taramasi Baslatiliyor...");
    startBLE();
    pBLEScan->start(SCAN_DURATION, false);
    
    // ADIM 2: BLE kapat (RAM serbest birak)
    stopBLE();
    Serial.printf(">>> Tarama bitti. Bulunan: %d | Free RAM: %d\n", studentCount, ESP.getFreeHeap());
    
    // ADIM 3: HTTP ile yoklama gonder (BLE kapali, RAM yeterli)
    int newRecords = 0;
    for (int i = 0; i < studentCount; i++) {
      if (!foundStudents[i].recorded) {
        markStudentPresent(foundStudents[i].hashStr);
        newRecords++;
        delay(300); 
      }
    }
    
    Serial.printf(">>> Kayit Tamamlandi. Toplam: %d | Yeni: %d\n", studentCount, newRecords);
  }
  delay(10);
}