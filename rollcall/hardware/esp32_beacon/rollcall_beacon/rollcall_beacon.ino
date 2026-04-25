#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEScan.h>
#include <BLEAdvertisedDevice.h>

// Scan süresi (saniye)
#define SCAN_TIME 10

// RollCall Öğrenci iBeacon UUID (küçük harf, tire yok)
// E2C56DB5-DFFB-48D2-B060-D0F5A71096B1
const uint8_t ROLLCALL_UUID[] = {
  0xE2, 0xC5, 0x6D, 0xB5, 0xDF, 0xFB, 0x48, 0xD2,
  0xB0, 0x60, 0xD0, 0xF5, 0xA7, 0x10, 0x96, 0xB1
};

// Beklenen Major ID (uygulamada 999 olarak ayarlandı)
const uint16_t EXPECTED_MAJOR = 999;

BLEScan* pBLEScan;
int appInstalledCount = 0;

// Bulunan öğrencilerin minor ID'lerini sakla (max 50)
uint16_t foundStudents[50];
int foundStudentCount = 0;

// iBeacon manufacturer data'dan UUID kontrolü yap
bool checkBeaconUUID(BLEAdvertisedDevice& device, uint16_t& outMajor, uint16_t& outMinor) {
  if (!device.haveManufacturerData()) return false;
  
  String mfData = device.getManufacturerData();
  
  // Minimum 24 byte olmali
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

class MyAdvertisedDeviceCallbacks: public BLEAdvertisedDeviceCallbacks {
    void onResult(BLEAdvertisedDevice advertisedDevice) {
      bool isAppInstalled = false;
      uint16_t major = 0, minor = 0;
      
      // iBeacon veya AltBeacon manufacturer data icinden UUID kontrolu
      if (checkBeaconUUID(advertisedDevice, major, minor)) {
        if (major == EXPECTED_MAJOR) {
          isAppInstalled = true;
        }
      }
      
      Serial.println("================================");
      Serial.print("Cihaz: ");
      Serial.println(advertisedDevice.haveName() ? advertisedDevice.getName().c_str() : "Bilinmeyen Cihaz");
      Serial.print("MAC: ");
      Serial.println(advertisedDevice.getAddress().toString().c_str());
      Serial.print("Sinyal: ");
      Serial.print(advertisedDevice.getRSSI());
      Serial.println(" dBm");
      
      Serial.print("RollCall Uygulama: ");
      if (isAppInstalled) {
          Serial.print("TRUE  |  Ogrenci No (Minor): ");
          Serial.println(minor);
          // Listeye ekle (tekrar eklememek için kontrol)
          bool alreadyFound = false;
          for (int i = 0; i < foundStudentCount; i++) {
            if (foundStudents[i] == minor) { alreadyFound = true; break; }
          }
          if (!alreadyFound && foundStudentCount < 50) {
            foundStudents[foundStudentCount++] = minor;
          }
          appInstalledCount++;
      } else {
          Serial.println("FALSE");
      }
      Serial.println("================================\n");
    }
};

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n====================================");
  Serial.println("  RollCall Akilli Yoklama Sistemi");
  Serial.println("  Ogrenci Tespit Modu");
  Serial.println("====================================\n");
  
  BLEDevice::init("");
  pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(new MyAdvertisedDeviceCallbacks());
  pBLEScan->setActiveScan(true); 
  pBLEScan->setInterval(100);
  pBLEScan->setWindow(99);
}

void loop() {
  appInstalledCount = 0;
  foundStudentCount = 0;
  
  Serial.println("\n--- TARAMA BASLIYOR ---");
  
  pBLEScan->start(SCAN_TIME, false);
  
  Serial.println("\n====================================");
  Serial.println("        TARAMA SONUCU");
  Serial.println("====================================");
  Serial.print("Toplam Cihaz       : ");
  Serial.println(pBLEScan->getResults()->getCount());
  Serial.print("Uygulama Yuklu     : ");
  Serial.println(appInstalledCount);
  Serial.print("Benzersiz Ogrenci  : ");
  Serial.println(foundStudentCount);
  
  if (foundStudentCount > 0) {
    Serial.println("------------------------------------");
    Serial.println("Bulunan Ogrenci Numaralari:");
    for (int i = 0; i < foundStudentCount; i++) {
      Serial.print("  -> ");
      Serial.println(foundStudents[i]);
    }
  }
  Serial.println("====================================\n");
  
  pBLEScan->clearResults();
  delay(5000); 
}