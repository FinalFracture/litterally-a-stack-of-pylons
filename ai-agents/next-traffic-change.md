# Next traffic change

Pending. These items were recorded ahead of the next traffic code change and are not done. Do them together on that pass. The playable project is this folder.

## Keep the whole car on the asphalt through turns

The Producer answered yes on 2026-10-03: the whole car body must stay on the asphalt through turns. A body corner about 0.1–0.2 m past the curb counts as off even when the center is still in the lane. On this pass, record that rule in TRAFFIC_AI.md.

Lane center is 1.75 m from the curb (ROAD_HALF 7 minus LANE_OFF 5.25). The car box is about 1.3 m wide and 2.6 m long, so a front corner sits about 1.45 m from the body center. A straight car centered in the lane is about 0.3 m inside the curb. A small yaw or an outside-of-lane bias puts a corner on the grass.

Evidence is the 2026-10-03 7:28 AM logs/traffic_drive.log beside this project (266 s). 29 off events. Closed clips are 0.02–0.23 s and 0.08–0.19 m at corners, center still on. nominal_s 493.20 is car-time with a corner at least 8 cm past the curb. Open episodes are not flushed, so a car that stays slightly off adds to that total without an "on" row.

## Path-change log

Add a second log beside traffic_drive.log. Write one row for every driving lane car each time its steered path changes. A change is a new polyline or a new kind (route, cones, pass, yield, escape, right, turn, hold, or an alt offer from _apply_alt). Sliding the cursor along the same polyline is not a change. traffic_drive.log stays as it is: it only prints a path slice on an off row or on a heading flip of the car nearest the player.

That log includes the moment a blockage is found, and a later row when the car has gotten around it. Found is _around_block when _close_block hits something inside BLOCK_CLOSE_M 16 and _holding starts, and also when _escaping starts from the idle wait or a low-intelligence leader. Gotten around is _passed_block (the block is more than 2 m behind travel) or the escape clear (the car has been off the asphalt and is back on the road more than 6 m past _block_at).

## One two-way road for pass practice

Reduce the play scene to one two-way road so passes can be watched and practiced. Three cars travel each direction. At each end a car U-turns onto the opposite lane and comes back, so the six keep meeting. Right-hand lanes stay LANE_OFF 5.25 on a ROAD_HALF 7 road. A U-turn uses the opposite lanes and bows outward. This replaces the closed loop from city._tuning_block and the ten Loop cars from traffic._city_cars for this observation. The later 36-car city fleet is not this scene.

Add helper functions that override the existing setup and the trip assignment. Do not modify the AI. driver.gd still chooses aim and speed, including passes. Do not edit TRAFFIC_AI.md for this scene. The helpers supply the single road, the six cars, and the end U-turn routes. The asphalt-through-turns rule above is the exception: that rule does go into TRAFFIC_AI.md.
