//
//  Movie+Lockup.swift
//  PopcornTime
//
//  Created by Tengis Batsaikhan on 5/05/2016.
//  Copyright © 2016 PopcornTime. All rights reserved.
//

import PopcornKit

extension Movie {

    var lockUp: String {
        var string = "<lockup actionID=\"showMovie»\(id)\">"
        string += "<img src=\"\(mediumCoverImage)\" width=\"250\" height=\"375\" />"
        string += "<title style=\"tv-text-highlight-style: marquee-and-show-on-highlight;\">\(title.cleaned)</title>"
        string += "</lockup>"
        return string
    }

}
