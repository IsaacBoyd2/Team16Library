#include <SoftwareSerial.h>
#include <SK6812.h>
#include "Arduino.h"
#include "RTClib.h"
#include "SD.h"

#define PIN_PROX 7                         //Proximity Sensor Pin
#define RX_PIN 2                           //BlueTooth Transiever Read Pin
#define TX_PIN 3                           //BlueTooth Transiever Write Pin

int systemState = 0;                       //Default System State

//Memory Subsystem Variables
String csvDataLine;                        //String being pulled from CSV on SD card sent over Bluetooth

RTC_DS3231 rtc;                            //Specific RTC Part
File myFile;                               //File variable that is set to file being opened on SD card

unsigned short timeStampCounter;           //Counter that counts up to 5 seconds to write a time stamp
int timeStampFlag;                         //Flag that is set so only one timestamp is taken

float currentTemp;                         //Current temperature in C
float tempThreshold = -20;                 //Temperature threshold to shut lights off (Default: -20C/-4F)

//User Detection Variables
short distanceReading;                     //Current proximity sensor reading
short distanceThreshold = 1600;            //Distance threshold needed to detect a user in close proximity range (Default: 1600mm/5ft)
unsigned short userTimer;                  //Timer that starts when a person leaves the close proximity range
int userDetectDelayFlag = 0;               //Flag that is set used in logic for when a user leaves close proximity range (0:Not in range | 1:Person in range | 2:Person leaves range)

//Lighting
int exteriorR = 0;                         //Exterior Lights Red Value         (Default: 0 out of 255)
int exteriorG = 0;                         //Exterior Lights Green Value       (Default: 0 out of 255)
int exteriorB = 255;                       //Exterior Lights Blue Value        (Default: 255 out of 255)
int exteriorW = 0;                         //Exterior Lights White Value       (Default: 0 out of 255)
int exteriorLmin = 25;                     //Exterior Lights Lux Minimum Value (Default: 25 out of 100)
int exteriorLmax = 100;                    //Exterior Lights Lux Maximum Value (Default: 100 out of 100)

int interiorR = 255;                       //Interior Lights Red Value         (Default: 255 out of 255)
int interiorG = 215;                       //Interior Lights Green Value       (Default: 215 out of 255)
int interiorB = 0;                         //Interior Lights Blue Value        (Default: 0 out of 255)
int interiorW = 0;                         //Interior Lights White Value       (Default: 0 out of 255)
int interiorL = 75;                        //Interior Lights Lux Value         (Default: 75 out of 100)

SK6812 RoofLED(30);                        //Exterior Roof Lights initialization  (30 LEDS)
SK6812 UnderLED(11);                       //Exterior Under Lights initialization (11 LEDS)
SK6812 InteriorLED(10);                    //Interior Lights initialization       (10 LEDS)

int daylightReading;                       //Current Daylight Sensor reading
int daylightThreshold = 1000;              //Daylight Sensor Threshold. When Reading is below Threshold, lights will turn on

int updateLightsFlag = 0;                  //Flag used to update lights only once upon update to prevent flickering

//Bluetooth Variables
SoftwareSerial bleSerial(RX_PIN, TX_PIN);  //Bluetooth Tranciever Pin Initialization
int bluetoothConnected;                    //Variable set when phone is connected or disconnected
char data[23];                             //Raw Packet of data that is recieved over Bluetooth
char *packet[2];                           //Formatted Packet of data
int ATcounter;                             //Counter used in timing of Bluetooth Transmission
int BTcounter;                             //Counter used in timing of Bluetooth Transmission
 
void setup() {
  Serial.begin(9600);           
  bleSerial.begin(9600);

  pinMode(4, INPUT);                       //Declare the Proximity Sensor as an input
  pinMode(PIN_PROX, INPUT);                //Declare the LED as an output  
  pinMode(10, OUTPUT);                     //Declare the Chip Select (CS) Pin for the SD card reader

  InteriorLED.set_output(5);               //Set output for Interior LEDs
  RoofLED.set_output(9);                   //Set output for Interior LEDs
  UnderLED.set_output(6);                  //Set output for Interior LEDs


  delay(1000);
  bleSerial.print("AT+PWRM1\r\n");         //Send AT Commands
  delay(1000);
  bleSerial.print("AT+POWE7\r\n");
  delay(1000);


  if (! rtc.begin()) {                     //Check that RTC is connected
    Serial.flush();
  }

  if (!SD.begin(10)) {                     //Check that SD card reader is connected
    Serial.flush();
  }

  rtc.adjust(DateTime(F(__DATE__), F(__TIME__))); //Adjust time on RTC to time of code compile
}

void loop() {
  currentTemp = rtc.getTemperature();                                       //Update Temperature reading
  
  if(digitalRead(4)){                                                       //Connect Phone to Bluetooth Tranciever
    BTcounter++;
  }else{
    BTcounter = 0;
    bluetoothConnected = 0;    
  }

  if(BTcounter >= 7){
    bluetoothConnected = 1;
  }

  daylightReading = analogRead(A0);                                         //Update Daylight Sensor reading
  distanceReading = pulseIn(PIN_PROX, HIGH);                                //Update Proximity Sensor reading
  
  if(bluetoothConnected){                                                   //If Phone is connected: System State = 1 (EDIT state)
    ATcounter++; 
    if(ATcounter > 15){
      systemState = 1;
      ATcounter = 0;
    }  
  }else if((distanceReading < 960) or (userDetectDelayFlag>0)){             //If User is in close proximity range: System State = 3 (ACTIVE state)
        systemState = 3;
        userDetectDelayFlag = 1;
  }else if(daylightReading < daylightThreshold){                            //If Dark enough outside: System State = 2 (LOW state)
      systemState = 2;
      timeStampCounter = millis();                                          //Save time when enter state 2, for 5 second timestamp counter
      timeStampFlag = 0;  
  }else{                                                                    //Else: System State = 0 (DORMANT state)
    systemState = 0;
    updateInteriorLights(0,0,0,0,0);
    updateExteriorLights(0,0,0,0,0);
    ATcounter = 0;

  }

  if((!bluetoothConnected) and (distanceReading > distanceThreshold)){      //If phone is disconnected, continuously try to reconnect
    enableNotifications();    
  }

  if(systemState == 1){                                                     //EDIT systemState
    
    bleSerial.readStringUntil('\n').toCharArray(data,23);                   //Read from Bluetooth Serial and format
    updateLightsFlag = 1;
    char *tempData = strtok(data, ",");
    for(int i = 0; i<2; i++){
      packet[i] = tempData;                                                 //Bluetooth Dat formatted in array of ascii strings
      tempData = strtok(NULL, ",");
    }
    
                                                                            //Data Format: [ID, Value]

    switch (atoi(packet[0])){                                               //Switch depending on ID recieved (packet[0])
      case 10:                                                              //ID 10: Change Distance Threshold
        distanceThreshold = atoi(packet[1]);
        break;
      case 11:                                                              //ID 11: Change Daylight Threshold
        daylightThreshold = (134+.936*(atoi(packet[1]))-((-.000641)*pow(atoi(packet[1]),2)));
        break;
      case 12:                                                              //ID 12: Get CSV button, downloads CSV of data on to phone
        readCSV();
        break;

    //EXTERIOR
      case 20:                                                              //ID 20: Change Exterior Red value
        exteriorR = atoi(packet[1]);
        break;
      case 21:                                                              //ID 21: Change Exterior Green value
        exteriorG = atoi(packet[1]);
        break;
      case 22:                                                              //ID 22: Change Exterior Blue value
        exteriorB = atoi(packet[1]);
        break;
      case 23:                                                              //ID 23: Change Exterior White value
        exteriorW = atoi(packet[1]);
        break;
      case 24:                                                              //ID 24: Change Exterior Lux Minimum value
        exteriorLmin = atoi(packet[1]);
        break;
      case 25:                                                              //ID 25: Change Exterior Lux Maximum value
        exteriorLmax = atoi(packet[1]);
        break;

    //INTERIOR
      case 30:                                                              //ID 30: Change Interior Red value
        interiorR = atoi(packet[1]);
        break;
      case 31:                                                              //ID 31: Change Interior Green value
        interiorG = atoi(packet[1]);
        break;
      case 32:                                                              //ID 32: Change Interior Blue value
        interiorB = atoi(packet[1]);
        break;
      case 33:                                                              //ID 33: Change Interior White value
        interiorW = atoi(packet[1]);
        break;
      case 34:                                                              //ID 34: Change Interior Lux value
        interiorL = atoi(packet[1]);
        break;

    //MISC    
      case 97:                                                              //ID 97: Set lights to Rainbow Mode
        rainbow();
        break;
      case 98:                                                              //ID 98: Re-sync time on RTC
        rtc.adjust(DateTime(packet[1]));
        break;
      case 99:                                                              //ID 99: Set lights to Fairy Mode
        Fairy();
        break;
      default:
        break;
      } 
  
    if(updateLightsFlag == 1){                                              //Update Lights only when change is made to prevent flickering
      updateExteriorLights(exteriorR, exteriorG, exteriorB, exteriorW, exteriorLmax);        
      updateInteriorLights(interiorR, interiorG, interiorB, interiorW, interiorL);
    }
    updateLightsFlag = 0; 
  }
  else if(systemState == 2){                                                //LOW systemState
    distanceReading = pulseIn(PIN_PROX, HIGH);                              //Update Proximity Reading

    if(distanceReading < distanceThreshold){                                //If person in distance range: calculate brightness, then update exterior brightness
      double exteriorLramp = double(exteriorLmax) - ((double(exteriorLmax)- double(exteriorLmin))/(double(distanceThreshold)-960.0))*(distanceReading-960.0);
      updateExteriorLights(exteriorR, exteriorG, exteriorB, exteriorW, int(exteriorLramp));
    }else{
      updateExteriorLights(exteriorR, exteriorG, exteriorB, exteriorW, exteriorLmin);       
    }
    updateInteriorLights(0,0,0,0,0);                                        //Exterior lights remain off
  }
  else if(systemState == 3){                                                //ACTIVE systemState
    userDetectDelayFlag = 1;

    if(daylightReading < daylightThreshold){                                //If dark enough outside: update lights to be at max brightness
      updateInteriorLights(interiorR, interiorG, interiorB, interiorW, interiorL);
      updateExteriorLights(exteriorR, exteriorG, exteriorB, exteriorW, exteriorLmax);
    }
    delay(3000);  

    unsigned short currentTime = millis();

    if((distanceReading > 960) and (userDetectDelayFlag = 1)){              //If person in inner range: start timmer
      userDetectDelayFlag = 2;
      unsigned short userTimer = millis();
    }

    if(((currentTime - userTimer) >= 5000) and (userDetectDelayFlag == 2)){ //If person has been in inner range for 5 seconds: take a time stamp
      userDetectDelayFlag = 0;
    }
    if(((currentTime - timeStampCounter) >= 5000)){
      
      if(timeStampFlag == 0){
        writeTimeStamp();
        timeStampFlag = 1;                                                  //Time stamp flag to only take one time stamp
        }

    }
  }
}




//Lighting Functions
void updateExteriorLights(int R, int G, int B, int W, int L){                 //Lighting Function to update the Exterior Lights
  if(currentTemp > tempThreshold){                                            //If warm enough
      RGBW updateColor = {((G*L)/100),((R*L)/100),((B*L)/100),((W*L)/100)};   //Format RGBW values and scale according to Lux
      for (int i = 0; i < 30; i++) {                                          //Loop through all diodes on strip (30 on Roof)
        RoofLED.set_rgbw(i, updateColor);                                     //Update individual dide
      }
      RoofLED.sync();
        
      for (int i = 0; i < 11; i++) {                                          //Loop through all diodes on strip (11 on Under)
        UnderLED.set_rgbw(i, updateColor);                                    //Update individual dide
      }
      UnderLED.sync();
    }
}

void updateInteriorLights(int R, int G, int B, int W, int L){                 //Lighting Function to update the Interior Lights
  if(currentTemp > tempThreshold){                                            //If warm enough
      RGBW updateColor = {((G*L)/100),((R*L)/100),((B*L)/100),((W*L)/100)};   //Format RGBW values and scale according to Lux
      for (int i = 0; i < 10; i++) {                                          //Loop through all diodes on strip (10 on Roof)
        InteriorLED.set_rgbw(i, updateColor);                                 //Update individual dide
      }
      InteriorLED.sync();
    }
}

void Fairy(){                                                                 //Fairy Mode Lighting Function
  for(int i = 0; i<10;i++){
    InteriorLED.set_rgbw(i, {105,255,180,0});
  }
  InteriorLED.sync();
  for(int i = 0; i<11;i++){
    UnderLED.set_rgbw(i, {0,127,255,0});
  }
  for(int i = 0; i<30;i++){
    RoofLED.set_rgbw(i, {0,127,255,0});
  }
  RoofLED.sync();
  UnderLED.sync();
  for(int i=0; i<100; i++){
    int Twinkle1= random(0,10);
    int Twinkle2= random(0,29);
    UnderLED.set_rgbw(Twinkle1, {0,127,255,150});
    RoofLED.set_rgbw(Twinkle2, {0,127,255,150});
    UnderLED.sync();
    RoofLED.sync();
    delay(100);
    UnderLED.set_rgbw(Twinkle1, {0,127,255,0});
    RoofLED.set_rgbw(Twinkle2, {0,127,255,0});
    UnderLED.sync();
    RoofLED.sync();
  }
}

void rainbow(){                                                               //Rainbow Mode Lighting Function
  unsigned int rgbColour[3];

  // Start off with red.
  rgbColour[0] = 255;
  rgbColour[1] = 0;
  rgbColour[2] = 0;  

  // Choose the colours to increment and decrement.
  for (int decColour = 0; decColour < 3; decColour += 1) {
    int incColour = decColour == 2 ? 0 : decColour + 1;

    // cross-fade the two colours.
    for(int i = 0; i < 255; i += 1) {
      rgbColour[decColour] -= 1;
      rgbColour[incColour] += 1;
      
      updateExteriorLights(rgbColour[0], rgbColour[1], rgbColour[2], 0, exteriorLmax);        
      updateInteriorLights(rgbColour[0], rgbColour[1], rgbColour[2], 0, interiorL);
      delay(10);
    }
  }
}


//Memory Functions
void writeTimeStamp(){                                                        //Write Time Stamp Memory Function

  DateTime now = rtc.now();                                                   //Get time from RTC

  myFile = SD.open("data.csv", FILE_WRITE);                                   //Open/Create data.csv file on SD card

  if (myFile) {
    char buf[] = "YYYY-MM-DD hh:mm:ss ";                                      //Format RTC time to IS0 8601
    myFile.println(now.toString(buf));                                        //Write time stamp to CSV line

    myFile.close();                                                           //Close file
  } else {
    Serial.println(F("error opening data.csv"));
  }
}

void readCSV(){                                                               //Read Time Stamps Memory Function
  myFile = SD.open("data.csv", FILE_READ);                                    //Open data.csv file

  if (!myFile) {
    Serial.println(F("Could not open data.csv"));
    return;
  }
  while (myFile.available()) {                                                //Loop through every line on CSV
    csvDataLine = myFile.readStringUntil('\n');                               
    csvDataLine = csvDataLine + "\n";
    delay(2);
    bleSerial.print(csvDataLine);                                             //Send Line over Bluetooth
  }
  delay(5);
  bleSerial.print("endCSV");                                                  //End of Transmission

  myFile.close();                                                             //Close file
}

//Bluetooth Functions
void enableNotifications() {                                                  //Reconnect Bluetooth
  // Enable notifications to keep the module on
  delay(200);
  bleSerial.print("AT+NOTI1\r\n");
  bluetoothConnected = 0;
  //delay(1000);
}