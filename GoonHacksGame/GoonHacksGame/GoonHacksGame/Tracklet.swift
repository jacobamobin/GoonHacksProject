//
//  Tracklet.swift
//  GoonHacksGame
//
//  VISEM tracklet data model for sperm movement
//

import Foundation
import CoreGraphics

// MARK: - Tracklet Data Models

struct TrackletData: Codable {
    let tracklets: [Tracklet]
    let globalStatistics: GlobalStatistics
    let metadata: Metadata

    enum CodingKeys: String, CodingKey {
        case tracklets
        case globalStatistics = "global_statistics"
        case metadata
    }
}

struct Tracklet: Codable {
    let id: String
    let videoId: String
    let `class`: Int  // 0=sperm, 1=cluster, 2=small_or_pinhead
    let length: Int
    let startFrame: Int
    let endFrame: Int
    let positions: [[Double]]  // [[x, y], [x, y], ...]
    let velocities: [[Double]] // [[vx, vy, magnitude], ...]
    let accelerations: [[Double]]
    let statistics: TrackletStatistics

    enum CodingKeys: String, CodingKey {
        case id
        case videoId = "video_id"
        case `class`
        case length
        case startFrame = "start_frame"
        case endFrame = "end_frame"
        case positions
        case velocities
        case accelerations
        case statistics
    }

    // Helper to get position at frame index
    func position(at index: Int) -> CGPoint? {
        guard index >= 0 && index < positions.count else { return nil }
        return CGPoint(x: positions[index][0], y: positions[index][1])
    }

    // Helper to get velocity at frame index
    func velocity(at index: Int) -> CGVector? {
        guard index >= 0 && index < velocities.count else { return nil }
        return CGVector(dx: velocities[index][0], dy: velocities[index][1])
    }

    // Get normalized time position (0.0 to 1.0) for warping/looping
    func position(atNormalizedTime t: Double) -> CGPoint? {
        let index = Int(t * Double(positions.count - 1))
        return position(at: index)
    }
}

struct TrackletStatistics: Codable {
    let meanSpeed: Double
    let stdSpeed: Double
    let maxSpeed: Double
    let straightness: Double  // 0.0-1.0, higher = straighter path
    let avgSize: Double
    let durationFrames: Int

    enum CodingKeys: String, CodingKey {
        case meanSpeed = "mean_speed"
        case stdSpeed = "std_speed"
        case maxSpeed = "max_speed"
        case straightness
        case avgSize = "avg_size"
        case durationFrames = "duration_frames"
    }
}

struct GlobalStatistics: Codable {
    let meanSpeed: Double
    let stdSpeed: Double
    let medianSpeed: Double
    let p95Speed: Double  // 95th percentile
    let meanStraightness: Double
    let medianStraightness: Double
    let totalTracklets: Int

    enum CodingKeys: String, CodingKey {
        case meanSpeed = "mean_speed"
        case stdSpeed = "std_speed"
        case medianSpeed = "median_speed"
        case p95Speed = "p95_speed"
        case meanStraightness = "mean_straightness"
        case medianStraightness = "median_straightness"
        case totalTracklets = "total_tracklets"
    }
}

struct Metadata: Codable {
    let fps: Int
    let coordinateSystem: String
    let classNames: [String]
    let minTrackletLength: Int
    let maxTracklets: Int

    enum CodingKeys: String, CodingKey {
        case fps
        case coordinateSystem = "coordinate_system"
        case classNames = "class_names"
        case minTrackletLength = "min_tracklet_length"
        case maxTracklets = "max_tracklets"
    }
}

// MARK: - Tracklet Loader

class TrackletLoader {
    static let shared = TrackletLoader()

    private(set) var data: TrackletData?

    func loadTracklets() -> TrackletData? {
        // Load from bundle
        guard let url = Bundle.main.url(forResource: "tracklets_for_game", withExtension: "json") else {
            print("❌ tracklets_for_game.json not found in bundle")
            return nil
        }

        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let trackletData = try decoder.decode(TrackletData.self, from: jsonData)

            self.data = trackletData
            print("✅ Loaded \(trackletData.tracklets.count) tracklets")
            print("   Mean speed: \(trackletData.globalStatistics.meanSpeed)")
            print("   Mean straightness: \(trackletData.globalStatistics.meanStraightness)")

            return trackletData
        } catch {
            print("❌ Error loading tracklets: \(error)")
            return nil
        }
    }

    // Get a random tracklet for CPU racer
    func randomTracklet() -> Tracklet? {
        guard let data = data else { return nil }
        return data.tracklets.randomElement()
    }

    // Get tracklets filtered by characteristics
    func tracklets(minSpeed: Double? = nil, minStraightness: Double? = nil) -> [Tracklet] {
        guard let data = data else { return [] }

        var filtered = data.tracklets

        if let minSpeed = minSpeed {
            filtered = filtered.filter { $0.statistics.meanSpeed >= minSpeed }
        }

        if let minStraightness = minStraightness {
            filtered = filtered.filter { $0.statistics.straightness >= minStraightness }
        }

        return filtered
    }
}
