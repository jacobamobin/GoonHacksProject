#!/usr/bin/env python3
"""
Extract sperm tracklets from VISEM CSV data for game physics.
Outputs JSON with trajectories, velocities, and statistics.
"""

import pandas as pd
import numpy as np
import json
from pathlib import Path
from collections import defaultdict

# Configuration
MIN_TRACKLET_LENGTH = 10  # Minimum frames to be useful
MAX_TRACKLETS = 100  # Limit for game performance
OUTPUT_FILE = "tracklets_for_game.json"

def calculate_velocity(positions, fps=30):
    """Calculate velocity between consecutive positions."""
    if len(positions) < 2:
        return []

    velocities = []
    for i in range(1, len(positions)):
        dx = positions[i][0] - positions[i-1][0]
        dy = positions[i][1] - positions[i-1][1]
        dt = 1.0 / fps
        vx = dx / dt
        vy = dy / dt
        velocities.append([vx, vy, np.sqrt(vx**2 + vy**2)])  # vx, vy, magnitude

    return velocities

def calculate_acceleration(velocities, fps=30):
    """Calculate acceleration between consecutive velocities."""
    if len(velocities) < 2:
        return []

    accelerations = []
    dt = 1.0 / fps
    for i in range(1, len(velocities)):
        dvx = velocities[i][0] - velocities[i-1][0]
        dvy = velocities[i][1] - velocities[i-1][1]
        ax = dvx / dt
        ay = dvy / dt
        accelerations.append([ax, ay, np.sqrt(ax**2 + ay**2)])

    return accelerations

def calculate_straightness(positions):
    """
    Calculate straightness ratio: displacement / path_length.
    1.0 = perfectly straight, 0.0 = very curved/circular
    """
    if len(positions) < 2:
        return 0.0

    # Direct displacement from start to end
    start = np.array(positions[0])
    end = np.array(positions[-1])
    displacement = np.linalg.norm(end - start)

    # Total path length
    path_length = 0.0
    for i in range(1, len(positions)):
        path_length += np.linalg.norm(
            np.array(positions[i]) - np.array(positions[i-1])
        )

    if path_length == 0:
        return 0.0

    return displacement / path_length

def extract_tracklets(csv_path, max_tracklets=MAX_TRACKLETS, min_length=MIN_TRACKLET_LENGTH):
    """Extract tracklets from VISEM bounding box CSV."""

    print(f"Loading data from {csv_path}...")
    df = pd.read_csv(csv_path, sep=' ')

    # Group by track ID (fid)
    print("Grouping by track ID...")
    tracks = defaultdict(list)

    for _, row in df.iterrows():
        frame_name = row['frame_name']
        fid = row['fid']
        class_id = row['class']

        # Parse frame number from frame_name (e.g., "11_frame_0_with_ftid" -> 0)
        parts = frame_name.split('_')
        video_id = parts[0]
        frame_num = int(parts[2])

        # Bounding box: center_x, center_y, width, height (normalized 0-1)
        bb_x = row['bb0']
        bb_y = row['bb1']
        bb_w = row['bb2']
        bb_h = row['bb3']

        tracks[fid].append({
            'frame': frame_num,
            'video_id': video_id,
            'class': class_id,
            'x': bb_x,
            'y': bb_y,
            'w': bb_w,
            'h': bb_h
        })

    print(f"Found {len(tracks)} unique tracks")

    # Process tracks into tracklets
    tracklets = []

    for fid, detections in tracks.items():
        # Sort by frame number
        detections.sort(key=lambda d: d['frame'])

        # Filter short tracks
        if len(detections) < min_length:
            continue

        # Extract positions (normalized coordinates)
        positions = [[d['x'], d['y']] for d in detections]

        # Calculate physics
        velocities = calculate_velocity(positions, fps=30)
        accelerations = calculate_acceleration(velocities, fps=30)
        straightness = calculate_straightness(positions)

        # Calculate statistics
        if velocities:
            speeds = [v[2] for v in velocities]  # magnitude
            mean_speed = np.mean(speeds)
            std_speed = np.std(speeds)
            max_speed = np.max(speeds)
        else:
            mean_speed = std_speed = max_speed = 0.0

        # Bounding box size (average)
        avg_size = np.mean([d['w'] * d['h'] for d in detections])

        # Build tracklet
        tracklet = {
            'id': fid,
            'video_id': detections[0]['video_id'],
            'class': int(detections[0]['class']),  # 0=sperm, 1=cluster, 2=small_or_pinhead
            'length': len(detections),
            'start_frame': detections[0]['frame'],
            'end_frame': detections[-1]['frame'],
            'positions': positions,
            'velocities': velocities,
            'accelerations': accelerations[:50] if accelerations else [],  # Limit size
            'statistics': {
                'mean_speed': float(mean_speed),
                'std_speed': float(std_speed),
                'max_speed': float(max_speed),
                'straightness': float(straightness),
                'avg_size': float(avg_size),
                'duration_frames': len(detections)
            }
        }

        tracklets.append(tracklet)

    # Sort by quality metrics (longer, faster, straighter = better for racing)
    tracklets.sort(
        key=lambda t: (
            t['statistics']['mean_speed'] *
            t['statistics']['straightness'] *
            np.log(t['length'])
        ),
        reverse=True
    )

    # Limit to max_tracklets
    tracklets = tracklets[:max_tracklets]

    print(f"Extracted {len(tracklets)} high-quality tracklets")

    # Calculate global statistics for physics tuning
    all_speeds = []
    all_straightness = []

    for t in tracklets:
        if t['velocities']:
            all_speeds.extend([v[2] for v in t['velocities']])
        all_straightness.append(t['statistics']['straightness'])

    global_stats = {
        'mean_speed': float(np.mean(all_speeds)) if all_speeds else 0.0,
        'std_speed': float(np.std(all_speeds)) if all_speeds else 0.0,
        'median_speed': float(np.median(all_speeds)) if all_speeds else 0.0,
        'p95_speed': float(np.percentile(all_speeds, 95)) if all_speeds else 0.0,
        'mean_straightness': float(np.mean(all_straightness)),
        'median_straightness': float(np.median(all_straightness)),
        'total_tracklets': len(tracklets)
    }

    return {
        'tracklets': tracklets,
        'global_statistics': global_stats,
        'metadata': {
            'fps': 30,
            'coordinate_system': 'normalized_0_1',
            'class_names': ['sperm', 'cluster', 'small_or_pinhead'],
            'min_tracklet_length': min_length,
            'max_tracklets': max_tracklets
        }
    }

def main():
    csv_path = Path("data_preparation_scripts/sperm_all_BBs.csv")

    if not csv_path.exists():
        print(f"Error: {csv_path} not found!")
        return

    # Extract tracklets
    data = extract_tracklets(csv_path)

    # Save to JSON
    output_path = Path(OUTPUT_FILE)
    print(f"\nSaving to {output_path}...")
    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)

    print(f"\n✓ Tracklets saved to {output_path}")
    print(f"\nGlobal Statistics:")
    print(f"  Mean speed: {data['global_statistics']['mean_speed']:.4f}")
    print(f"  Std speed: {data['global_statistics']['std_speed']:.4f}")
    print(f"  P95 speed: {data['global_statistics']['p95_speed']:.4f}")
    print(f"  Mean straightness: {data['global_statistics']['mean_straightness']:.4f}")
    print(f"\nReady for Swift integration!")

if __name__ == "__main__":
    main()
