import CoreBluetooth
import SwiftUI
import Combine

//Variables used for syncing time
var globalvar: [String] = [""]
var logString = ""
var showText = false



//Pull the actual time of of the phone for syncing
func getCurrentTimestamp() -> String
{
        let currentDate = Date()
        let formattedDateString = dateFormatter.string(from: currentDate)
        return formattedDateString
}

//Format the date for syncing timestamps.
let dateFormatter: DateFormatter =
{
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
}()



//This class is what enables blueooth connections. In this class you will find functions that do the following things.

// Send data
// Recieve data
// Format data
// enable communications

class BluetoothManager: NSObject, ObservableObject
{
    
    //Declare a variable that communicates with the built in iOS bluetooth
    private var centralManager: CBCentralManager!
    //Declare a peripheral (HM-19)
    private var peripheral: CBPeripheral!
    //Declare a state variable for  our peripheral
    var writableCharacteristic: CBCharacteristic?
    
    //Declare information buffers
    @Published var receivedString = ""
    @Published var toCSV = [[String]]()
    @Published var trueDataArray = []
    
    //We need to initilize stuff here, but we are not in conent view. This allows us to initilize stuff within a class.
    override init()
    {
        //Declare our iOS bluetooth interface
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
}


//Here we create an extension of the class in order to handle adding our peripherals to the native iOS stuff.
extension BluetoothManager: CBCentralManagerDelegate
{
    
    //This function looks for our specific devices hardware uuid and tried to connect to it
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    {
        if central.state == .poweredOn
        {
            //let uuid = UUID(uuidString: "D27387D3-6304-D919-687E-99FE9C4B14B3")
            //let uuid = UUID(uuidString: "A0B6B6B7-0147-D0D9-88B2-198CC08D83CD")
            //let uuid = UUID(uuidString: "84B57431-9E29-9F0A-BF53-1553F202FD88") //Dr. Becker's
            let uuid = UUID(uuidString: "8FBCCFFA-2E68-3C70-5CE7-8FE88D14E017")
            let peripherals = central.retrievePeripherals(withIdentifiers: [uuid!])
            if let peripheral = peripherals.first
            {
                self.peripheral = peripheral
                central.connect(peripheral,options: nil)
            }
        }
    }

    //Keep advertising connection just in case we do not conect initially
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {}
    
    //Once we connect and have found our peripheral add it as our peripheral
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
}

//Here we handle our periphearls.
extension BluetoothManager: CBPeripheralDelegate
{
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        guard let services = peripheral.services else { return }
        for service in services
        {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    //We want our periphearl to be writable and readable. Basically thing function allows us to make it this.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics
        {
            if characteristic.properties.contains(.notify)
            {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            
            //Added for sending
            if characteristic.properties.contains(.write)
            {
                self.writableCharacteristic = characteristic
            }
            
            //Here we are syncing the time stamps. After we connect the timestamps will be synced after 6s. This allows time to send firmware commands to the HM-19.
            //This value could be decreased on increased if the spnosr desires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6)  //6s delay
            {
                //Here we construct a package of data to send. We will do this a lot later on in the program, however, here is a good example of it.
                //xxxx22 contains what we are trying to send
                //id422 contains the id that we are sending.
                //yyyyyyy22 contains a new line character that the arduino uses to detect a transmission.
                
                //We then package these into an array and send the pack using the sendData() function.
                let xxxx22 = getCurrentTimestamp()
                let id422 = String(98)
                let yyyyyyy22 = "\n"
                let starray422 = [id422, xxxx22, yyyyyyy22]
                let joined422 = starray422.joined(separator: ",")
                let data522 = joined422.data(using: .utf8)
                self.sendData(data: data522!)
            }
        }
    }
    
    //This function's job is to put the information from the HM-19 into an array whenever it is recieved
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        print(toCSV)
        guard let value = characteristic.value else { return }
        if let string = String(data: value, encoding: .utf8)
        {

            receivedString = string
            print(receivedString)
            
            
            if receivedString.contains("endCSV")
            {
                generateCSV()
            }
            
            if !toCSV.contains([receivedString]) && !receivedString.contains("AT")  && !receivedString.contains("endCSV")
            {
                toCSV.append([receivedString])
            }
            else{
                showText = true
            }
            
            
            
            
        }
        
    }
    
    //Built in function used to send data to a peripheral "HM-19"
    func sendData(data: Data)
    {
        if let peripheral = self.peripheral, let characteristic = self.writableCharacteristic
        {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    //This function recieves data from the HM-19 and calls
    func generateCSV()
    {
        
        //Make a file to write to
        
        let sFileName = "\(getCurrentTimestamp()).csv"
        let documentDirectoryPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as String
        let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
        let output = OutputStream.toMemory()
        let csvWriter = CHCSVWriter(outputStream: output, encoding: String.Encoding.utf8.rawValue, delimiter: ",".utf16.first!)
        
        //This is what is going into the CSV "physically"
        // Header
        // Timestamp 1,
        // Timestamp 2, etc.
        
        // HEADER FOR THE CSV FILE
        
        //csvWriter?.writeField("User DATA")
        csvWriter?.finishLine()
        
        for(elements) in toCSV.enumerated()
        {
            csvWriter?.writeField(elements.element[0])
            csvWriter?.finishLine()
        }
        
        csvWriter?.closeStream()
        
        let buffer = (output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)!
        
        do
        {
            try buffer.write(to: documentURL)
        }
        catch
        {
            
        }
        
    }
}

//This is the start of the front end functionality of the App. Everyting before this is essentially what handled the bluetooth and CSV backend. What you should expect ot find in the following section is the following.

// UI components.
// Persistant memory assignments.
// Logic for sending data.

struct ContentView: View
{
    	
    
    @State private var isLoading = true
    
    //On initilization we want to through in values from persistant memory
    // This is what is used to save colors on the slider (save slider positions)
    
    init()
    {
        
        
        
        
        //Find this file on the devices (if it does not exist it should be created here automatically)
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("savedData2.csv")
        
        //Once it is found we are going to extract the components.
        do
        {
            //Grab everything out of the file in string format
            let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            //Seperate them by newline characters
            let dataArray = fileContents.components(separatedBy: "\n")
            //Set this as a global array so that is can be accessed throughout the program
            globalvar = dataArray
        }
        //If something goes wrong throw an error. (file not found usually)
        catch
        {
            print("Error reading file: \(error)")
        }
    }
    
    //Thie view is what will enable the UI component of the program
    var body: some View
    {

        Home(sl1width1: CGFloat(Int(globalvar[11])!),sl1width2: CGFloat(Int(globalvar[12]) ?? 0), sliderValue1: Float(Int(globalvar[7])!), sliderValue2: Float(Int(globalvar[8])!), sliderValue3: Float(Int(globalvar[9])!), sliderValue4: Float(Int(globalvar[10])!), sliderValue5: Float(Int(globalvar[0])!), sliderValue6: Float(Int(globalvar[0])!), sliderValue7: Float(Int(globalvar[5])!),sliderValue8: Float(Int(globalvar[6])!), IntRed: globalvar[0], IntGreen: globalvar[1], IntBlue: globalvar[2], IntWhite: globalvar[3], IntBrightnessMax: globalvar[4], Distance: globalvar[5], Lux: globalvar[6], ExtRed: globalvar[7], ExtGreen: globalvar[8], ExtBlue: globalvar[9], ExtWhite: globalvar[10], ExtBrightnessMin: globalvar[11], ExtBrightnessMax: globalvar[12])

        //Home(sl1width1: 0, sl1width2: 0, sliderValue1: 0, sliderValue2: 0, sliderValue3: 0, sliderValue4: 0, sliderValue5: 0, sliderValue6: 0, sliderValue7: 0,sliderValue8: 0,IntRed: "0", IntGreen: "0", IntBlue: "0", IntWhite: "0", IntBrightnessMax: "0", Distance: "0", Lux: "0", ExtRed: "0", ExtGreen: "0", ExtBlue: "0", ExtWhite: "0", ExtBrightnessMin: "0", ExtBrightnessMax: "0")
        }
    
    
    
    
}



//This home view contains the UI components and the logic behind sending values to the HM-19
struct Home: View {
    
    //Variables to store dynamic states of sliders
    @State var sl1width1 : CGFloat
    @State var sl1width2 : CGFloat
    
    @State var sliderValue1 : Float
    @State var sliderValue2 : Float
    @State var sliderValue3 : Float
    @State var sliderValue4 : Float
    @State var sliderValue5 : Float
    @State var sliderValue6 : Float
    @State var sliderValue7 : Float
    @State var sliderValue8 : Float
    
    
    //Toggle values
    @State var toggleValue1 = true
    @State var toggleValue2 : Float = 0.0
    @State var counter : Int = 0
    
    //Current colors and other values (used in persistant memory)
    @State var IntRed : String
    @State var IntGreen : String
    @State var IntBlue : String
    @State var IntWhite : String
    @State var IntBrightnessMax : String
    
    @State var Distance : String
    @State var Lux : String
    
    @State var ExtRed : String
    @State var ExtGreen : String
    @State var ExtBlue : String
    @State var ExtWhite : String
    @State var ExtBrightnessMin : String
    @State var ExtBrightnessMax : String
    @State var which : String = "Exterior"
    
    //Find the width of the screen
    var totalWidth = UIScreen.main.bounds.width - 60
    
    //Set a default color for the brightness threshold
    @State private var circleColor = Color.gray
    
    //Now declare bluetoothManager as an object that we can reference.
    @StateObject var bluetoothManager = BluetoothManager()
    
    
    //Now we will define the shape of the UI and put in the UI components with it.
    
    
    
    var body: some View
    {
        //Veriticlly stack (Vstack)
        VStack
        {
            if showText {
                            Text("Connected")
                                .font(.headline)
                                .padding()
                        }
            else{
                Text("Disconnected")
                    .font(.headline)
                    .padding()
            }
            //Toggle switch (upper right corner) The text will change depending on the state of the toggle switch
            Toggle("\(which): is being editted", isOn: $toggleValue1).onChange(of: toggleValue1)
            {
                //This value in function allows for thing to happen on a change. Essentiall it allows for logic within ui components.
                value in
                
                //If we are trying to edit the exterior lights.
                if self.toggleValue1 == true{
                    which = "Exterior"
                    sliderValue1 = Float(ExtRed)!
                    sliderValue2 = Float(ExtGreen)!
                    sliderValue3 = Float(ExtBlue)!
                    sliderValue4 = Float(ExtWhite)!
                    sl1width1 = CGFloat(Float(ExtBrightnessMin)!)
                    sl1width2 = CGFloat(Float(ExtBrightnessMax)!)
                }
                if self.toggleValue1 == false{
                    which = "Interior"
                    sliderValue1 = Float(IntRed)!
                    sliderValue2 = Float(IntGreen)!
                    sliderValue3 = Float(IntBlue)!
                    sliderValue4 = Float(IntWhite)!
                    
                    sl1width2 = CGFloat(Float(IntBrightnessMax)!)
                }
                
            }

            
            
            
            //First set of sliders Red-exterior/Red-interior
            HStack{
                
                Text("Red").tint(Color.red).frame(width:105,height:20, alignment: .leading)
                
                Slider(value: $sliderValue1, in: 0...255, step: 1){editing in
                    
                    
                    
                    
                    if self.toggleValue1 == false{
                        let x = String(describing: Int(sliderValue1))
                        let id = String(30)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        
                        self.IntRed = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }
                        
                        
                        
                        
                       

                        
                    }
                
                    if self.toggleValue1 == true{
                        let x = String(describing: Int(sliderValue1))
                        let id = String(20)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        
                        self.ExtRed = x
                        
                        //self.ExtGreen = String(sliderValue2)
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }
                    }
                    
                }.padding().tint(Color.red)
                
                Text("\(Int(sliderValue1))").frame(width:50,height:20, alignment: .trailing)
                
            }
            
            HStack{
                
                Text("Green").tint(Color.green).frame(width:105,height:20, alignment: .leading)
                
                Slider(value: $sliderValue2, in: 0...255, step: 1){editing in
                    
                    if self.toggleValue1 == false{
                        let x = String(describing: Int(sliderValue2))
                        let id = String(31)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        
                        self.IntGreen = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }

                    }
                
                    if self.toggleValue1 == true{
                        let x = String(describing: Int(sliderValue2))
                        let id = String(21)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        self.ExtGreen = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }
                    }

                    
                }.padding().tint(Color.green)
                
                Text("\(Int(sliderValue2))").frame(width:50,height:20, alignment: .trailing)
                
            }
            
            
            
            
            //Third Set of Sliders blue-interior/blue-exterior
            
            HStack{
                
                Text("Blue").tint(Color.blue).frame(width:105,height:20, alignment: .leading)
                
                Slider(value: $sliderValue3, in: 0...255, step: 1){editing in
                    
                    if self.toggleValue1 == false{
                        let x = String(describing: Int(sliderValue3))
                        let id = String(32)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        
                        self.IntBlue = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }

                    }
                
                    if self.toggleValue1 == true{
                        let x = String(describing: Int(sliderValue3))
                        let id = String(22)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        
                        self.ExtBlue = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }
                    }
                    
                }.padding().tint(Color.blue)
                
                Text("\(Int(sliderValue3))").frame(width:50,height:20, alignment: .trailing)
                
            }
            
            
            
            HStack{
                
                Text("White").tint(Color.white).frame(width:105,height:20, alignment: .leading)
                
                Slider(value: $sliderValue4, in: 0...255, step: 1){editing in
                    
                    if self.toggleValue1 == false{
                        let x = String(describing: Int(sliderValue4))
                        let id = String(33)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        
                        self.IntWhite = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }

                    }
                
                    if self.toggleValue1 == true{
                        let x = String(describing: Int(sliderValue4))
                        let id = String(23)
                        let yyyy = "\n"
                        let starray = [id, x, yyyy]
                        let joined = starray.joined(separator: ",")
                        let data2 = joined.data(using: .utf8)
                        self.counter = self.counter + 1
                        if counter == 2{
                            NSLog("Time")
                            bluetoothManager.sendData(data: data2!)
                            self.counter = 0
                            print(starray)
                        }
                        
                        self.ExtWhite = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }
                    }
                    
                }.padding().tint(Color.white)
                
                Text("\(Int(sliderValue4))").frame(width:50,height:20, alignment: .trailing)
                
            }
            
            
            
            HStack{
                Text("Brightness").frame(width:95,height:20, alignment: .leading)
                Spacer()
                ZStack(alignment: .leading){
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 223,height: 4)
                    if self.toggleValue1 == true{
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: self.sl1width2 - self.sl1width1+10, height: 4)
                            .offset(x: self.sl1width1+24)
                    }
                    
                    if self.toggleValue1 == false{
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: self.sl1width2, height: 4)
                            .offset(x: 0)
                    }
                    
                    HStack(spacing: 0){
                        
                        
                        if self.toggleValue1 == true{
                            Circle()
                                .fill(Color.white)
                                .frame(width: 26, height: 26)
                                .shadow(color: .gray, radius: 2)
                                .offset(x: self.sl1width1)
                                .gesture(
                                    
                                    DragGesture()
                                    
                                        .onChanged({(value) in
                                            
                                            //print(sl1width1)
                                            //print("seperator")
                                            //print(sl1width2)
                                            
                                            
                                            if value.location.x >= 0 && value.location.x <= self.sl1width2 && value.location.x <= 215{
                                                self.sl1width1 = value.location.x}
                                            
                                            if self.toggleValue1 == false{self.toggleValue2 = 0}
                                            if self.toggleValue1 == true{self.toggleValue2 = 1}
                                            
                                            
                                            
                                            
                                            
                                            
                                        })
                                    
                                        .onEnded({(value) in
                                            
                                            
                                            
                                            
                                            if self.toggleValue1 == true{
                                                let x = String(describing: Int(sl1width1*100/180))
                                                let id = String(24)
                                                let yyyy = "\n"
                                                let starray = [id, x, yyyy]
                                                let joined = starray.joined(separator: ",")
                                                let data2 = joined.data(using: .utf8)
                                                
                                                bluetoothManager.sendData(data: data2!)
                                                NSLog("Time")
                                                self.counter = 0
                                                print(starray)
                                                
                                                self.ExtBrightnessMin = String(describing: Int(sl1width1))
                                                
                                                let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                                                
                                                let sFileName = "savedData2.csv"
                                                
                                                guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                                                    print("Could not find document directory")
                                                    return
                                                }
                                                
                                                let fileURL = dir.appendingPathComponent(sFileName)
                                                
                                                //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                                                let joinedStrings = array.joined(separator: "\n")
                                                do {
                                                    try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                                                } catch {
                                                    print("Error writing to file: \(error)")
                                                }
                                                
                                            }
                                            
                                            
                                            
                                        })
                                    
                                    
                                )
                        }
                        Circle()
                            .fill(Color.white)
                            .frame(width: 26, height: 26)
                            .shadow(color: .gray, radius: 2)
                            .offset(x:self.sl1width2)
                            .gesture(
                                
                                DragGesture()
                                
                                    .onChanged({(value) in
                                        
                                   
                                        if self.toggleValue1 == true{
                                            if value.location.x <= self.totalWidth && value.location.x >= self.sl1width1 && value.location.x <= 180{
                                                self.sl1width2 = value.location.x}
                                        }
                                        if self.toggleValue1 == false{
                                            
                                            if value.location.x <= self.totalWidth && value.location.x >= self.sl1width1 && value.location.x <= 210{
                                                self.sl1width2 = value.location.x}
                                        }
                                    
                                    if self.toggleValue1 == false{self.toggleValue2 = 0}
                                    if self.toggleValue1 == true{self.toggleValue2 = 1}
                                    
                                  
                                    
                                })
                                
                                    .onEnded({(value) in
                                        
                                        
                                        
                        
                                        
                                        if self.toggleValue1 == true{
                                            let x = String(describing: Int(sl1width2*100/180))
                                            let id = String(25)
                                            let yyyy = "\n"
                                            let starray = [id, x, yyyy]
                                            let joined = starray.joined(separator: ",")
                                            let data2 = joined.data(using: .utf8)
                                            
                                                bluetoothManager.sendData(data: data2!)
                                            NSLog("Time")
                                                self.counter = 0
                                                print(starray)
                                            
                                            
                                            self.ExtBrightnessMax = String(describing: Int(sl1width2))
                                            let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                                            
                                            let sFileName = "savedData2.csv"
                                            
                                            guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                                                print("Could not find document directory")
                                                return
                                            }
                                            
                                            let fileURL = dir.appendingPathComponent(sFileName)
                                            
                                            //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                                            let joinedStrings = array.joined(separator: "\n")
                                            do {
                                                    try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                                                } catch {
                                                    print("Error writing to file: \(error)")
                                                }
                                            
                                        }
                                        
                                        if self.toggleValue1 == false{
                                            let x = String(describing: Int(sl1width2*100/210))
                                            let id = String(34)
                                            let yyyy = "\n"
                                            let starray = [id, x, yyyy]
                                            let joined = starray.joined(separator: ",")
                                            let data2 = joined.data(using: .utf8)
                                    
                                          
                                                bluetoothManager.sendData(data: data2!)
                                            NSLog("Time")
                                                self.counter = 0
                                                print(starray)
                                            
                                            self.IntBrightnessMax = String(describing: Int(sl1width2))
                                            
                                            let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                                            
                                            let sFileName = "savedData2.csv"
                                            
                                            guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                                                print("Could not find document directory")
                                                return
                                            }
                                            
                                            let fileURL = dir.appendingPathComponent(sFileName)
                                            
                                            //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                                            let joinedStrings = array.joined(separator: "\n")
                                            do {
                                                    try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                                                } catch {
                                                    print("Error writing to file: \(error)")
                                                }
                                            

                                        }
                                        
                                    })
                                
                            )
                    }
                }
                VStack{
                    if self.toggleValue1 == true{
                        Text("\(Int(sl1width1*100/180))").frame(width:53,height:20, alignment: .trailing)
                        Text("\(Int(sl1width2*100/180))").frame(width:53,height:20, alignment: .trailing)
                    }
                    if self.toggleValue1 == false{
                        Text("\(Int(sl1width2*100/210))").frame(width:53,height:48, alignment: .trailing)
                    }
                }
            }
        
            HStack{
                
                Text("Distance").tint(Color.purple).frame(width:105,height:20, alignment: .leading)
                
                Slider(value: $sliderValue7, in: 961...3840, step: 1){editing in
                    
                    
                    let x = String(describing: Int(sliderValue7))
                    let id = String(10)
                    let yyyy = "\n"
                    let starray = [id, x, yyyy]
                    let joined = starray.joined(separator: ",")
                    let data2 = joined.data(using: .utf8)
                    self.counter = self.counter + 1
                    if counter == 2{
                        bluetoothManager.sendData(data: data2!)
                        NSLog("Time")
                        self.counter = 0
                        print(starray)
                        
                        self.Distance = x
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }
                    }

                    
                
                    

                    
                }.padding().tint(Color.purple)
                
                Text("\(Int(sliderValue7/304.8))").frame(width:50,height:20, alignment: .trailing)
                
            }
            HStack{
                
                Text("Dark\nThreshold").tint(Color.purple).frame(width:105,height:70, alignment: .leading)
                
                Slider(value: $sliderValue8, in: 0...999, step: 1){editing in
                    
                    circleColor = Color(hue: 0.16, saturation: 0.7, brightness: Double(sliderValue8)/Double(999))
                    
                    let current_color = circleColor.description
                    
                    //print(String(circleColor))
                    
                    let x = String(describing: Int(sliderValue8))
                    let id = String(11)
                    let yyyy = "\n"
                    let starray = [id, x , yyyy]
                    let joined = starray.joined(separator: ",")
                    let data2 = joined.data(using: .utf8)
                    self.counter = self.counter + 1
                    if counter == 2{
                        bluetoothManager.sendData(data: data2!)
                        NSLog("Time")
                        self.counter = 0
                        print(starray)
                        
                        self.Lux = x
                        
                        
                        
                        let array = [self.IntRed,self.IntGreen,self.IntBlue,self.IntWhite, self.IntBrightnessMax, self.Distance, self.Lux, self.ExtRed, self.ExtGreen, self.ExtBlue, self.ExtWhite, self.ExtBrightnessMin, self.ExtBrightnessMax]
                        
                        let sFileName = "savedData2.csv"
                        
                        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                            print("Could not find document directory")
                            return
                        }
                        
                        let fileURL = dir.appendingPathComponent(sFileName)
                        
                        //let documentURL = URL(fileURLWithPath: documentDirectoryPath).appendingPathComponent(sFileName)
                        let joinedStrings = array.joined(separator: "\n")
                        do {
                                try joinedStrings.write(to: fileURL, atomically: false, encoding: .utf8)
                            } catch {
                                print("Error writing to file: \(error)")
                            }
                    }

                    
                }.padding().tint(Color.purple)
                
                
                Circle()
                    .fill(circleColor)
                    .frame(width: 30, height: 30)
                //Text("\(Int(sliderValue8))").frame(width:35,height:20, alignment: .trailing)
                
            }
            
            VStack
            {
                
                HStack{
                    
                    
                    
                    Button(action: {
                        let id = "99"
                        let yyyy = "\n"
                        let starray = [id, yyyy]
                        let joined = starray.joined(separator: ",")
                        guard let data = joined.data(using: .utf8) else { return }
                        bluetoothManager.sendData(data: data)
                        NSLog("Time")
                        bluetoothManager.generateCSV()
                        print(starray)
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.headline)
                            Text("Fairy Mode")
                                .fontWeight(.semibold)
                                .font(.title2)
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.pink, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .gray, radius: 5, x: 0, y: 5)
                    }
                    
                    Button(action: {
                        let id = "12"
                        let yyyy = "\n"
                        let starray = [id, yyyy]
                        let joined = starray.joined(separator: ",")
                        guard let data = joined.data(using: .utf8) else { return }
                        bluetoothManager.sendData(data: data)
                        NSLog("Time")
                        //print(bluetoothManager.toCSV)
                        //bluetoothManager.generateCSV()
                        //print("Button press")
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.headline)
                            Text("Get CSV Data")
                                .fontWeight(.semibold)
                                .font(.title2)
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .gray, radius: 5, x: 0, y: 5)
                    }
                    
                    
                    
                }
                
                Button(action: {
                    let id = "97"
                    let yyyy = "\n"
                    let starray = [id, yyyy]
                    let joined = starray.joined(separator: ",")
                    guard let data = joined.data(using: .utf8) else { return }
                    bluetoothManager.sendData(data: data)
                    NSLog("Time")
                }) {
                    Text("Rainbow")
                        .fontWeight(.semibold)
                        .font(.title2)
                        .padding()
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .gray, radius: 5, x: 0, y: 5)
                }
            }
            

            
            
        }.scaleEffect(1).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray.opacity(0.25))
        //Change scaling affect to fit your size. (0.85 for phone, 1 for ipad.)
        
    }
}
