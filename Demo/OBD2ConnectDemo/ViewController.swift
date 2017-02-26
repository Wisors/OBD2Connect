//
//  ViewController.swift
//  OBD2ConnectDemo
//
//  Created by Alex Nikishin on 04/02/2017.
//  Copyright © 2017 Wisors. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    let connection = OBDConnection()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        connection.onStateChanged = { state in
            print(state)
        }
        connection.open()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(4)) {
            
            self.connection.send(data: "ATZ\r".data(using: .ascii)!) { data in
                
                data.onSuccess { data in
                    print(data)
                }

                data.onFailure { error in
                    print(String(describing: error))
                }
            }
        }
    }
}

