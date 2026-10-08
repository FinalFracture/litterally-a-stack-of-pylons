# Traffic AI

Rules locked with the Producer while designing vehicle driving. The playtest map is a closed loop of roads, two four-way stops, sidewalk pedestrians, and up to ten cars. Every car uses the same driver. This file is the rulebook. `scripts/driver.gd` follows it.

Intelligence and aggression are a dice roll plus modifiers.

## Scores

Every vehicle has two scores.

- **Intelligence** is rolled when the car appears and stays the same for as long as that car exists.
- **Aggression** is separate. Each car has a randomized base. Red lights, traffic jams, and similar delays raise aggression. While traffic is flowing, aggression falls back down to that base.
- A higher aggression score makes the car pull out to pass a slower car sooner. How long it follows before passing depends on aggression.
- There is no patience score. Lines about patience wearing out mean aggression.

## Destination

Every car has a real place on the map it is trying to reach. It drives toward that place. It only loops when the path to the destination requires a loop.

When it arrives, one of these three outcomes is chosen at random.

1. It despawns after it enters an area that hides it, or once it is far enough from the player to despawn safely.
2. It parks, and this only happens at a designated parking spot. The doors open, a pedestrian gets out, and the doors close.
3. It waits at least a minute, then picks a new destination.

This playtest does not use those three. On arrival the car picks another place on the loop and keeps driving. The park, exit, and despawn functions stay in the file and are not called. Stop signs still hold the car.

## Path

A generated path is at least 200 meters when the roads allow it. The car keeps that path. It does not replace the path until it is close to a blockage, or until an obstacle moves onto the path it is already following.

Reversing keeps the nose pointed the way it started. The car moves backward along the route. It does not turn the nose around to face the backup direction.

When the route doubles back, the car turns around on the asphalt. It does not keep driving past the end of the road.

Pathfinding finds a way around cones, and around a stopped crashed car the same way.

Cones also suggest paths. All pathfinding infers its path from the cones. When the cones suggest a new path, the car uses that path. Directing cars with cones is a major part of the game.

The car follows a cone-suggested path even when that path leaves its normal lane, and even when the path leads into another car, a pedestrian, or an object. A high-intelligence car does not refuse that path. Cone paths win over that judgment.

Cones are guideposts. The car infers a path from them. It does not treat a cone as a spot to drive over.

Which side of a line of cones the car drives on depends on the side the car approaches from. The car stays on the side of the line it is already on, and it does not cross through the cones.

A cone line on the far side of the yellow line does not replace the route. The car is on that side only to get around a blockage. Those cones stay obstacles. The car goes around them on the asphalt and returns to its own lane. Following a cone line stays on the asphalt.

A cone path does not win over a red light. The car still stops when the light is red and it has not entered the intersection. Once the light is green, the car follows the cone path.

After the car passes the last cone in that suggestion, it returns to the normal route toward its destination. It does not stop on the last cone or on the curb. The end of that line is on the asphalt, and the car keeps driving.

The path stays on the asphalt until a leave-asphalt rule below says otherwise.

The oncoming lane is for avoiding an obstacle or passing a slower car. Once the car is past that obstacle, it returns to its own lane.

Most of the time the car waits until the oncoming lane is clear before it enters. Some of the time it does not, so a crash can happen. Those crashes should feel natural and should not be frequent.

If an oncoming car appears while this car is already in the oncoming lane, intelligence decides the reaction. A high-intelligence car evaluates and either stops safely or goes back. A low-intelligence car may speed up to get in front, or it may dive back into its own lane. Either of those low-intelligence moves can cause an accident when another car is there.

When both sides of an obstacle are open, the car's own lane, or at least its own direction of traffic, is the default. That default is not a hard requirement.

If an obstacle moves into the path the car is already following, the car recalculates.

## Obstacles

- A cone is an obstacle, and a group of cones can also suggest the path the car should take.
- A stopped crashed car is an obstacle. Other cars path around it.
- A pedestrian is an obstacle. The car paths around them.
- The player is not an obstacle. Cars ignore the player.

## Gaps

A car guesses whether it will fit through a gap. The guess depends on its intelligence. It then goes through with more or less caution, or it stays put when the gap looks too narrow for that car.

A more cautious car leaves more room between itself and the obstacle.

If a car stays put because it will not try a gap, that wait counts for every car in the line. Each car leaves the asphalt only when it reaches the blockage.

A low-intelligence car follows a lead car that has decided to leave the asphalt, and it takes that same path.

A higher-intelligence car reaches the blockage, judges a gap if one is there, weighs the other caveats, and leaves the asphalt once it is worn out.

## Leaving the asphalt

A car that has not been moving for a long time can get frustrated and drive off the asphalt.

- Time spent waiting at a red light, still short of the intersection, does not count toward that. The light cycle is shorter than ten seconds. Once the light is green, sitting still counts.
- Time spent waiting at a stop sign does count toward that.
- Time stuck in a traffic jam counts for every car. Intelligence and aggression change how soon the car is willing, not whether the jam counts.
- A car that has not moved about 1.6 m, and is not in that red-light wait, has to be moving again before ten seconds. Around four seconds it leaves on the near shoulder. If that shoulder is blocked it tries the other one. If it is still stuck it reverses, nose forward, when the road behind is open, then takes a new route. If that still does not free it, it drives off the asphalt anyway. Braking for the vehicle it is going around does not cancel this escape, and a turn closer than 45 m does not cancel it either. If the body is still wedged after that, the car drives onto a clear stretch of road at a modest speed, nose kept, and takes a new route. It does not jump there, and it does not slide sideways along a wall. A slide along a wall does not count as getting free.
- Once the car is past the blockage, it gets back onto the asphalt as soon as it can. The return is on the roadway, in from the curb. The car does not stop where the grass meets the asphalt.
- The car leaves on the shoulder of the side it is already on. That is its right, the near curb, not the far side of the road.
- It drives around the cones on that shoulder and stays on that path until it is past them. It does not cross back through the cones.
- It is not past the blockage until it has been off the asphalt and come back on beyond the cones. Driving through the cones while still on the road does not count.

## Speed and turns

Through a turn, the car follows the curve of its own lane. The turn is as smooth as it can be.

The whole car body stays on the asphalt through turns. The body corners count: a corner 0.1–0.2 m past the curb is off the road even when the center stays in its lane.

The car slows down while it is turning. As soon as the turn is finished, it returns to its normal speed.

Roads have speed limits. Global aggression thresholds turn speeding on once they are exceeded. A car at its base aggression is not automatically at the speed limit. Base aggression sets how far over the limit the car goes when it is speeding. Crossing a higher threshold makes the car speed by a larger share of that base aggression.

While one car follows another, it keeps a gap so the two do not touch. Acceleration, braking, and follow distance are set from that car's aggression and intelligence. Higher aggression means a shorter follow gap. Higher intelligence means a longer follow gap.

## Intersections

When the car's way through an intersection is clear, it drives through without stopping.

If it has already entered an intersection with a stop light, it finishes the crossing even when the light turns red after it entered. If the light is red and the car has not entered yet, it stops.

When the car ahead is stopped at a red light, this car waits behind it. If this car's current path already includes a right turn there, high aggression can make it take that right turn off the asphalt. That turn still goes around pedestrians.

A four-way stop keeps a list of the cars that arrived and runs like a real four-way stop.

- The car that arrived first is the next one to go.
- A car coming from the opposite direction may also proceed.
- The stop tracks whether a car is turning.
- The other car's intelligence decides whether it is clear to proceed.
- Traffic does not sit in a logic stalemate. The car with the lower intelligence causes the accident. This applies to every stalemate, not only four-way stops.

## Crashes

How bad a crash is depends on the physics, including speed and mass.

- **Bad.** Both cars stay stopped where they collided. Pedestrians exit and stand on the sidewalk. A wrecker arrives and picks up the crashed cars.
- **Moderate.** Both cars pull off the asphalt and the people exit.
- **Very light.** The cars ignore it and both continue on their way.

## Wreckers and other emergency vehicles

A wrecker uses this same driving logic, plus emergency-response contingencies.

On the way to a crash, a wrecker stops for a red light. At a four-way stop, a wrecker waits its turn like any other car.

Emergency vehicles other than wreckers may ignore lights and stop signs. Other cars move aside safely, clear the intersection, or stop on a green light to let them through. At a stop sign, a regular car lets an emergency vehicle through even when it is the regular car's turn. On a straight road, a regular car pulls over to let an emergency vehicle pass.
