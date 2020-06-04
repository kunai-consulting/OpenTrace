//
//  DeviceRepository.swift
//  SocialDistanceSDK
//
//  Created by Piotr on 28/05/2020.
//  Copyright © 2020 kunai. All rights reserved.
//

import UIKit
import CoreData
import AudioToolbox

public protocol DeviceRepositoryListener {
    func onRepositoryUpdate()
}

// https://stackoverflow.com/questions/41698466/cocoa-touch-framework-coredata
class PersistentContainer: NSPersistentContainer {

}

public class DeviceRepository {
    
    public var currentListener: DeviceRepositoryListener? = nil
    
    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        
        let container = PersistentContainer(name: "Social_Distance_Alarm")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    public static let sharedInstance: DeviceRepository = {
        let instance = DeviceRepository()
        // setup code
        return instance
    }()
    
    func insert(deviceUuid: String, rssi: Int32, txPower: Int32?, scanDate: Date, isAndroid: Bool) {
        // Add the device to the database
        let newDevice = Device(context: self.context)
        newDevice.deviceUuid = deviceUuid
        newDevice.rssi = rssi
        newDevice.isAndroid = isAndroid
        if (txPower != nil) {
            newDevice.txPower = txPower!
        }
        
        newDevice.scanDate = scanDate

        // TODO: remove old devices
    }
    
    func updateCurrentDevices() {
        do {
            try context.save()
        } catch {
            print("Error saving context \(error)")
        }
        
        currentListener?.onRepositoryUpdate()
        doAlerts()
    }
    
    func doAlerts() {
        var tooClose = false
        var danger = false
        var warn = false
        for device in getCurrentDevices() {
            let signal = Util.signlaStrength(rssi: device.rssi, txPower: device.txPower)
            
            if (signal >= AppConstants.signalDistanceStrongWarn) {
                tooClose = true
            } else if (signal >= AppConstants.signlaDistanceLightWarn) {
                danger = true
            } else if (signal >= AppConstants.signalDistanceOk) {
                warn = true
            }
        }
        
        // Warn about proximity with feeback
        if (tooClose) {
            AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(kSystemSoundID_Vibrate)) {
                AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(kSystemSoundID_Vibrate)) {
                    AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(kSystemSoundID_Vibrate)) { }
                    
                }
            }
            
            
        } else if (danger) {
            AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(kSystemSoundID_Vibrate)) {
                AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(kSystemSoundID_Vibrate)) { }
            }
        } else if (warn) {
            AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(1520)) { }
        }
    }
    
    public func getCurrentDevices() -> [Device] {
        var deviceArray = [Device]()
        let startTime = (Date() - AppConstants.traceInterval) as NSDate
        let timePredicate = NSPredicate(format: "scanDate >= %@", startTime)
        let request: NSFetchRequest<Device> = Device.fetchRequest()
        request.predicate = timePredicate
        let sortDesc = NSSortDescriptor(key: "rssi", ascending: false)
        request.sortDescriptors = [sortDesc]
        
        do {
            deviceArray = try context.fetch(request)
        } catch {
            print("Error fetching current devices \(error)")
        }
        
        // Remove duplicate scans and average the values
        var averagedDevices = [Device]()
        for device in deviceArray {
            let current = averagedDevices.first(where: {$0.deviceUuid?.lowercased() == device.deviceUuid?.lowercased()})
            if (current != nil) {
                current!.rssi = (current!.rssi + device.rssi) / 2
                current!.txPower = (current!.txPower + device.txPower) / 2
            } else {
                averagedDevices.append(device)
            }
        }
        
        return averagedDevices
    }
    
    public func getAllDevices() -> [Device] {
        var deviceArray = [Device]()
        let request: NSFetchRequest<Device> = Device.fetchRequest()
        let sortDesc = NSSortDescriptor(key: "scanDate", ascending: false)
        request.sortDescriptors = [sortDesc]
        
        do {
            deviceArray = try context.fetch(request)
        } catch {
            print("Error fetching all devices \(error)")
        }
        
        return deviceArray
    }
}

extension DeviceRepository: BluetoothManagerDelegate {
    public func peripheralsDidUpdate() {
        // Not used by the current Social Distance Alarm app
    }
    
    public func advertisingStarted() {
        // Not used by the current Social Distance Alarm app
    }
    
    public func scanningStarted() {
        // This gets called every time the scanning cycle loops
        // so we are using it to make sure the UI is up to date
        currentListener?.onRepositoryUpdate()
    }
    
    public func didDiscoverPeripheral(uuid: String, rssi: NSNumber, txPower: NSNumber?, isAndroid: Bool) {
        insert(deviceUuid: uuid, rssi: rssi.int32Value, txPower: txPower?.int32Value, scanDate: Date(), isAndroid: isAndroid)
        updateCurrentDevices()
    }
    
    
}