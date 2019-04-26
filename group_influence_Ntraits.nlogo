globals [
  uniform? ; variable to track if all nodes have the same value
  groups ; a list of lists (members of each group)
]

turtles-own [
  group
  probability_flip ; probability node will be influenced by a neighbor
  trait
  same_as_neighbors? ; true if node and all neighbors have the same value
]


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Functionality for setup ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Create nodes
to setup
  clear-all
  setup-nodes
  setup-groups
  init-info
  if network_configuration = "spatially_clustered" [
    setup-spatially-clustered-network
  ]
  if network_configuration = "random" [
    setup-random-network
  ]
  ;; connect any disconnected nodes
  ask turtles [
    if count link-neighbors = 0 [ create-link-with one-of other turtles ]
  ]
  reset-ticks
end

;; Keeps configuration, resets information
to reset
  init-info
end

to setup-nodes
  create-turtles num_nodes [
    set shape "circle"
    set color blue
    setxy (random-xcor * 0.95) (random-ycor * 0.95)
    setup-flip
  ]
end

to setup-flip
  ;; assigns a probability to each node
  ;; P(it will flip | it meets another node that is different)
  if flip_distribution = "uniform" [
    set probability_flip 1 ; all nodes will flip on every tick
  ]
  if flip_distribution = "normal" [
    set probability_flip random-normal 0.5 0.341
  ]
  if flip_distribution = "random" [
    set probability_flip random-float 1
  ]
end

to setup-groups
  ;; groups are assigned without consideration of given neighborly attachments
  ;; the assigned group provides information to identify an instantaneous sub-network without enforcing continuous attachment
  ;; the probability that two nodes in the same group are linked neighbors is proportional to probability_join_group/num_groups
  set groups []
  ask turtles [
    ;; probability_join_group = universal variable for all nodes
    if random-float 1 < probability_join_group [
      set group random num_groups ; retuns random int within range of global 'num-groups
      ;; color indicates group
      set color group + 2 ; plus some int so that a node is not black
    ]
  ]
  ;; fill global 'groups' variable with lists of all nodes in each group
  let i 0
  while [ i < num_groups] [
    let new_group turtles with [ group = i ]
    if any? new_group [ set groups (lput new_group groups) ]
    set i (i + 1)
  ]
  ;; need to update number of groups, because they are chosen at random, may not initialize to exact number
  set num_groups (length groups)
end

to init-info
  if initial_info_distribution = "random" [
    ask turtles [
      set trait random num_distinct_traits
      set size (trait + 1) ; so that a node is not invisible if value = 0
    ]
  ]
  if initial_info_distribution = "uniform" [
    ;; enforce an about uniform distribution of traits
    let track 0 ; counting variable
    ask turtles [
      set trait track
      set size (trait + 1) ; so that a node is not invisible if value = 0
      set track (track + 1)
      if track = num_distinct_traits [
        set track 0
      ]
    ]
  ]
  if initial_info_distribution = "skewed" [
    ;; let one trait be skewed
    let mean_trait (num_distinct_traits / 2)
    if mean_trait mod 1 >= 0.5 [ set mean_trait ceiling mean_trait ]
    if mean_trait mod 1 < 0.5 [ set mean_trait floor mean_trait ]
    ask turtles [
      let t random-exponential mean_trait
      ;; enforce integer values of traits of possible such that traits are not mutable
      let i 0
      let min_dist 100
      ;; find the integer trait value that is closest to the t value
      let trait_save 0
      while [i < num_distinct_traits] [
        let check abs(t - i)
        if check < min_dist [
          set trait_save (i)
          set min_dist (check)
        ]
        set i (i + 1)
      ]
      set trait (trait_save)
      set size (trait + 1)
    ]
  ]
end

to setup-spatially-clustered-network
  let num_links (avg_node_degree * num_nodes) / 2
  while [count links < num_links] [
    ask one-of turtles [
      let choice (min-one-of (other turtles with [not link-neighbor? myself]) [distance myself])
      if choice != nobody [ create-link-with choice]
    ]
  ]
  ;; change layout
  repeat 20 [
    layout-spring turtles links 0.3 (world-width / (sqrt num_nodes)) 1
  ]
end

to setup-random-network
  ask turtles [
    let std_dev ((avg_node_degree / 0.5) * 0.341) ; for a normal distribution around avg_node_degree
    let degree random-normal avg_node_degree std_dev
    if degree = 0 [ set degree 1 ]
    let i 0
    while [i < degree] [
      create-link-with one-of other turtles
      set i (i + 1)
    ]
  ]
  ;; change layout
  repeat 20 [
    layout-spring turtles links 0.9 (world-width / (sqrt num_nodes)) 1
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Functionality for go ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  check-spread
  while [ uniform? = FALSE ] [
    if uniform_meeting_time and length groups != 0 [
      groups-meet-uniform
    ]
    if not uniform_meeting_time and length groups != 0 [
      groups-meet-nonuniform
    ]
    ;; each turtle attempts to influence its neighbors
    ask turtles [
      let new_trait trait ; take turtle's value
      ask link-neighbors [
        if random-float 1 < probability_flip [
          ;; turtle influences neighbor
          ;; turtles will always copy
          set trait new_trait
          set size (trait + 1)
        ]
      ]
    ]
    check-spread
    tick
  ]
  stop
end

to check-spread
  ;; check to see if all turtles have the same value
  ask turtles [
    let check_trait trait
    set same_as_neighbors? all? link-neighbors [ trait = check_trait ]
  ]
  set uniform? all? turtles [ same_as_neighbors? = TRUE ]
end

to groups-meet-uniform
  ;; groups all meet on the same tick with given frequency
  if ticks mod meeting_frequency = 0 [
    foreach groups [ members ->
      ;; determine value for group
      let group_trait 0
      if group_action = "random copy" [
        ;; everyone copies a random member
        ask one-of members [
          set group_trait trait
        ]
      ]
      if group_action = "high influencer" [
        let max_deg 0
        ask members [
          let deg count link-neighbors
          if deg > max_deg [
            set group_trait trait
            set max_deg deg
          ]
        ]
      ]
      ;; assign value to group members
      ask members [
        set trait group_trait
        set size (trait + 1)
      ]
    ]
  ]
end

to groups-meet-nonuniform
  ;; groups all meet on different ticks
  let i 0
  let split ceiling (meeting_frequency / num_groups)
  while [ i < num_groups ] [
    let group_offset meeting_frequency + (i * split)
    if ticks mod group_offset = 0 [
      ;; group 'i' meets
      let members (item i groups)
      ;; determine value for group
      let group_trait 0
      if group_action = "random copy" [
        ;; everyone copies a random member
        ask one-of members [
          set group_trait trait
        ]
      ]
      if group_action = "high influencer" [
        let max_deg 0
        ask members [
          let deg count link-neighbors
          if deg > max_deg [
            set group_trait trait
            set max_deg deg
          ]
        ]
      ]
      ;; assign value to group members
      ask members [
        set trait group_trait
        set size (trait + 1)
      ]
    ]
    set i (i + 1)
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
318
10
816
509
-1
-1
10.0
1
10
1
1
1
0
1
1
1
-24
24
-24
24
1
1
1
ticks
30.0

SLIDER
19
10
291
43
num_nodes
num_nodes
10
100
100.0
1
1
NIL
HORIZONTAL

CHOOSER
19
88
155
133
network_configuration
network_configuration
"spatially_clustered" "random"
0

CHOOSER
16
364
296
409
flip_distribution
flip_distribution
"uniform" "normal" "random"
2

SLIDER
832
12
1008
45
probability_join_group
probability_join_group
0
1
1.0
0.1
1
NIL
HORIZONTAL

BUTTON
18
464
82
497
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
1017
77
1196
110
uniform_meeting_time
uniform_meeting_time
1
1
-1000

SLIDER
160
89
289
122
avg_node_degree
avg_node_degree
1
10
7.0
1
1
NIL
HORIZONTAL

BUTTON
88
464
151
497
NIL
go\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
17
277
294
322
initial_info_distribution
initial_info_distribution
"random" "uniform" "skewed"
2

CHOOSER
831
86
1008
131
group_action
group_action
"random copy" "high influencer"
0

SLIDER
832
49
1008
82
num_groups
num_groups
0
50
13.0
1
1
NIL
HORIZONTAL

SLIDER
1202
77
1347
110
meeting_frequency
meeting_frequency
1
50
10.0
1
1
NIL
HORIZONTAL

PLOT
833
184
1230
325
Trait counts 
Time
Value
0.0
0.0
0.0
0.0
true
true
"" ""
PENS
"trait 0" 1.0 0 -2674135 true "" "plot count turtles with [trait = 0]"
"trait 1" 1.0 0 -955883 true "" "plot count turtles with [trait = 1]"
"trait 2" 1.0 0 -6459832 true "" "plot count turtles with [trait = 2]"

PLOT
833
343
1231
506
Standard Deviation
NIL
NIL
0.0
0.0
0.0
0.0
true
true
"" ""
PENS
"Variance" 1.0 0 -16777216 true "" "plot standard-deviation [trait] of turtles"

TEXTBOX
21
52
292
84
Try: random and lower avg_node_degree, spatially_clustered and higher avg_node_degree
11
0.0
1

TEXTBOX
1018
12
1351
73
If uniform_meeting_time on, then all groups meet at same time with given frequency. If off, then each group given a random offset by which they meet with the given frequency. \n[ further application -> non uniform meeting frequency ]
11
0.0
1

TEXTBOX
16
330
310
358
flip_distribution: distribution of probabilities assigned to each node that it will be influenced by its neighbor
11
0.0
1

TEXTBOX
19
201
311
271
initial_info_distribution: given N possible traits for a node to claim, does a node claim a trait randomly, is a node assigned a trait to enforce a uniform distribution, or is a node assigned a trait such that one trait dominates among all nodes
11
0.0
1

BUTTON
158
465
221
498
NIL
reset
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
17
431
301
460
Note: use 'reset' to re-initialize information on the same network configuration and groups
11
0.0
1

TEXTBOX
77
153
227
171
NIL
11
0.0
1

INPUTBOX
19
137
156
197
num_distinct_traits
3.0
1
0
Number

TEXTBOX
164
136
314
206
num_distinct_traits: number of different traits a node can adopt. traits are always copied. Try: 2 or 3
11
0.0
1

TEXTBOX
833
160
1195
194
TODO: add more graph plots, depending on num_distinct_traits
11
0.0
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

Preferential Attachment
Virus on a Network 
Random Network 
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
