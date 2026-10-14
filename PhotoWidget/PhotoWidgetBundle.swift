//
//  PhotoWidgetBundle.swift
//  PhotoWidget
//
//  Created by Adrian Yusufa Rachman on 05/06/26.
//

import WidgetKit
import SwiftUI

@main
struct PhotoWidgetBundle: WidgetBundle {
    var body: some Widget {
        PhotoWidget()
        if #available(iOS 18.0, *) {
            ShufflePhotosControl()
        }
    }
}
