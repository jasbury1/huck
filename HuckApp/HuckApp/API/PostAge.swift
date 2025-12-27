//
//  PostAge.swift
//  HuckApp
//
//  Created by James Asbury on 12/27/25.
//

import Foundation

enum PostAge {
    case now
    case minutes(Int)
    case hours(Int)
    case days(Int)
    case years(Int)
    case unknown
    
    static func age(from date: Date) -> PostAge {
        let now = Date.now
        let dateInterval = DateInterval(start: date, end: now)
        let timeInterval = dateInterval.duration
        if timeInterval < 60 {
            return .now
        }
        if timeInterval < 60 * 60 {
            let minutes = Int(timeInterval / 60)
            return .minutes(minutes)
        }
        if timeInterval < 60 * 60 * 24 {
            let hours = Int(timeInterval / (60 * 60))
            return .hours(hours)
        }
        // Days and years must factor in calendar complexities
        let calendarDiff = Calendar.current.dateComponents([.hour, .minute, .year, .month, .day],
                                                           from: date,
                                                           to: now)
        if let years = calendarDiff.year, years > 0 {
            return .years(years)
        }
        if let days = calendarDiff.day {
            return .days(days)
        }
        return .unknown
    }
}

extension Date {
    func ageString() -> String {
        let age = PostAge.age(from: self)
        return switch age {
        case .now:
            "now"
        case let .minutes(m):
            "\(m)m"
        case let .hours(h):
            "\(h)h"
        case let .days(d):
            "\(d)d"
        case let .years(y):
            "\(y)y"
        case .unknown:
            "unknown"
        }
    }
}
