# Search Taxonomy - Hierarchical Tag Relationships

This document describes how search terms expand to find related photos. The system uses a **one-way hierarchical expansion**:

- **Superclass → Subclass**: Searching "pet" finds dogs, cats, birds
- **Subclass → Subclass**: Searching "dog" does NOT find cats (no cross-contamination)

## Principle

```
Superclass (broad)
    ├── Subclass (specific)
    │       └── Variant (very specific)
    └── Subclass
            └── Variant
```

Searching at any level finds everything BELOW it, but nothing ABOVE or SIDEWAYS.

---

## 🐾 ANIMALS

### Hierarchy
```
animal
├── pet
│   ├── dog → puppy, canine, hound, poodle, terrier, retriever, bulldog, beagle
│   ├── cat → kitten, feline, tabby, siamese, persian
│   ├── bird → parrot, sparrow, pigeon, crow, eagle, owl, duck, chicken
│   ├── fish → goldfish, salmon, tuna, tropical fish
│   ├── hamster, rabbit/bunny, turtle, guinea pig
│   └── horse → pony, stallion, mare, foal
│
├── wildlife
│   ├── lion → lioness, cub, pride
│   ├── tiger → cub, bengal, siberian
│   ├── elephant → tusks, trunk, herd
│   ├── bear → grizzly, polar bear, panda, cub
│   ├── wolf → pack, howl, coyote
│   ├── fox → vixen, kit
│   ├── deer → doe, fawn, buck, stag, elk, moose
│   ├── monkey → ape, chimpanzee, gorilla, orangutan, primate
│   └── zebra, giraffe, leopard, cheetah, rhino, hippo, buffalo
│
├── marine
│   ├── whale → orca, humpback, blue whale
│   ├── dolphin → porpoise, orca
│   ├── shark → great white, hammerhead, tiger shark
│   ├── fish, octopus, jellyfish, crab, lobster, seahorse, starfish, coral, seal
│
├── insect
│   ├── butterfly → moth, caterpillar, monarch
│   ├── bee → bumblebee, honeybee, wasp, hornet
│   ├── ant, beetle, dragonfly, ladybug, fly, mosquito, grasshopper, cricket
│
├── bug → insect, beetle, ant, spider, cockroach
│   └── spider → tarantula, web, arachnid
│
├── reptile
│   ├── snake → python, cobra, viper, boa, serpent
│   ├── lizard → gecko, iguana, chameleon, monitor
│   ├── turtle → tortoise, sea turtle
│   └── crocodile, alligator
│
└── frog → toad, tadpole, amphibian
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `animal` | Everything above | - |
| `pet` | dog, cat, bird, fish, hamster, rabbit | lion, tiger (wildlife) |
| `dog` | puppy, poodle, terrier, retriever | cat, bird, other pets |
| `cat` | kitten, tabby, siamese | dog, bird |
| `wildlife` | lion, tiger, elephant, bear, wolf | dog, cat (pets) |
| `marine` | whale, dolphin, shark, fish, octopus | dog, cat |
| `insect` | butterfly, bee, ant, beetle | spider (in bug) |

---

## 🍕 FOOD

### Hierarchy
```
food
├── cuisine → pizza, pasta, sushi, burger, taco, curry, ramen, steak, seafood, barbecue
├── meal → breakfast, lunch, dinner, brunch, supper
├── dessert → cake, pie, cookie, ice cream, chocolate, pastry, donut, candy
├── snack → chips, popcorn, nuts, crackers, pretzel
├── drink/beverage
│   ├── coffee → espresso, latte, cappuccino, mocha
│   ├── tea → green tea, black tea, herbal tea
│   ├── juice, water, soda
│   └── alcohol → beer, wine, cocktail, whiskey, vodka, champagne
│
└── Specific items (no upward expansion):
    ├── pizza → pizzas, pie
    ├── pasta → spaghetti, noodle, macaroni, lasagna
    ├── sushi → sashimi, maki, nigiri
    ├── burger → hamburger, cheeseburger
    └── cake → cupcake, birthday cake, wedding cake
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `food` | Everything edible | - |
| `cuisine` | pizza, pasta, sushi, burger, steak | cake (dessert) |
| `dessert` | cake, pie, ice cream, cookie | pizza, burger |
| `pizza` | pizzas, pie | sushi, burger, pasta |
| `drink` | coffee, tea, juice, beer, wine | cake, pizza |
| `coffee` | espresso, latte, cappuccino | tea, juice |

---

## 👥 PEOPLE

### Hierarchy
```
people
├── person → human, man, woman, child, adult
├── family → parent, child, baby, grandparent, sibling
├── crowd → group, audience, gathering, team
│
└── Specific (no upward expansion):
    ├── man → male, gentleman, guy
    ├── woman → female, lady, girl
    ├── child → kid, boy, girl, toddler
    ├── baby → infant, newborn, toddler
    ├── selfie → portrait, headshot
    └── portrait → headshot, selfie, face
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `people` | person, family, crowd, man, woman, child | - |
| `family` | parent, child, baby, grandparent | crowd, team |
| `man` | male, gentleman, guy | woman, child |
| `selfie` | portrait, headshot | crowd, group |

---

## 🏞️ PLACES/SCENERY

### Hierarchy
```
scenery
├── nature
│   ├── beach → coast, shore, seaside, sand
│   ├── ocean → sea, marine, wave
│   ├── mountain → hill, peak, summit, alpine
│   ├── forest → woods, jungle, woodland
│   ├── lake → pond, reservoir
│   ├── sunset → sunrise, dusk, dawn, golden hour
│   └── waterfall, valley, field, meadow, desert
│
├── outdoor → park, garden, beach, mountain, forest, camping, hiking
│   ├── park → garden, playground
│   └── garden → yard, lawn, backyard, greenhouse
│
├── urban → city, street, building, downtown, skyline, architecture
│   └── city → downtown, metropolitan, skyline
│
└── water → ocean, sea, lake, river, pool, waterfall, stream, pond, wave
    ├── pool → swimming pool, swimming
    └── waterfall → cascade, falls
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `scenery` | beach, mountain, city, park, nature | - |
| `nature` | beach, forest, sunset, flower, sky | city, street |
| `outdoor` | park, garden, camping, hiking | indoor, room |
| `urban` | city, street, building, skyline | beach, forest |
| `beach` | coast, shore, seaside, sand | mountain, lake |
| `water` | ocean, lake, pool, waterfall | rain (weather) |

---

## 🌤️ WEATHER/SKY

### Hierarchy
```
weather → rain, snow, storm, cloud, sunny, fog, wind, lightning
├── rain → rainy, rainfall, drizzle, shower, wet
├── snow → snowy, snowfall, blizzard, frost, ice, winter
├── storm → thunder, lightning, tempest, hurricane, tornado
├── fog → mist, haze, foggy, misty
└── cloud → clouds, cloudy, overcast

sky → cloud, sunset, sunrise, blue sky, night sky, stars, moon, sun
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `weather` | rain, snow, storm, cloud, fog | sunset (in sky) |
| `sky` | cloud, sunset, sunrise, stars, moon | rain, storm |
| `rain` | rainy, drizzle, shower | snow, storm |
| `storm` | thunder, lightning, hurricane | rain, fog |

---

## 🚗 VEHICLES

### Hierarchy
```
vehicle
├── car → automobile, sedan, coupe, convertible, suv, van
├── truck → pickup, semi, lorry
├── motorcycle → motorbike, scooter, moped
├── bicycle → bike, cycle, cycling
├── boat → ship, yacht, sailboat, canoe, kayak
├── airplane → plane, aircraft, jet, helicopter
└── train → railway, locomotive, subway, metro

bike → bicycle, motorcycle (ambiguous - matches both)
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `vehicle` | car, truck, boat, airplane, train | - |
| `car` | sedan, SUV, convertible | truck, motorcycle |
| `boat` | ship, yacht, sailboat, canoe | car, airplane |
| `bike` | bicycle AND motorcycle | car, truck |

---

## 📱 ELECTRONICS

### Hierarchy
```
electronics
├── computer → laptop, desktop, pc, mac, monitor, keyboard
├── phone → smartphone, mobile, cellphone, iphone, android
├── tv/television → monitor, screen, display
├── camera → dslr, lens, photography
└── gaming → console, playstation, xbox, nintendo, controller

screen → display, monitor
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `electronics` | computer, phone, tv, camera | furniture |
| `computer` | laptop, desktop, pc, monitor | phone, tv |
| `phone` | smartphone, mobile, iphone, android | computer |
| `gaming` | console, playstation, xbox | computer (general) |

---

## 🎉 EVENTS/ACTIVITIES

### Hierarchy
```
event
├── party → celebration, birthday party, gathering
├── wedding → marriage, bride, groom, ceremony
├── birthday → birthday party, birthday cake, celebration
├── holiday → christmas, thanksgiving, easter, halloween, new year
├── vacation → travel, trip, tourism, holiday
├── concert → music, performance, show, live
└── festival → carnival, fair, celebration

sport
├── soccer/football → futbol, goal, pitch
├── basketball → hoop, court, dunk
├── tennis → racket, court, serve
├── golf → club, course, putting, green, tee
├── swimming → pool, swim, diving, swimmer
├── running → jogging, marathon, sprint, track
├── cycling → biking, bicycle, bike, cyclist
├── skiing → snowboard, ski, slope, alpine
├── surfing → surf, wave, board, surfer
├── gym → workout, fitness, exercise, weights, training
└── yoga → meditation, stretch, pose, mat
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `event` | party, wedding, birthday, concert | sport |
| `wedding` | bride, groom, marriage, ceremony | birthday, party |
| `sport` | soccer, basketball, tennis, swimming | concert, party |
| `gym` | workout, fitness, exercise, weights | yoga, swimming |

---

## 🎵 MUSIC

### Hierarchy
```
music
├── instrument
│   ├── guitar → acoustic, electric, bass guitar, ukulele
│   ├── piano → keyboard, keys, grand piano
│   ├── drums → drum, percussion, cymbal, drumstick
│   ├── violin, flute, saxophone, trumpet, cello, harp
│
├── concert → gig, show, performance, live music, festival
├── band, orchestra, singer, musician
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `music` | instrument, concert, band, guitar, piano | - |
| `instrument` | guitar, piano, drums, violin, all instruments | concert, band |
| `guitar` | acoustic, electric, bass, ukulele | piano, drums |
| `concert` | gig, show, performance, live | instrument |

---

## 🎨 ART/CREATIVE

### Hierarchy
```
art
├── painting → canvas, oil painting, watercolor, acrylic, mural
├── drawing → sketch, illustration, doodle, pencil
├── sculpture → statue, carving, figurine, bust
├── illustration → drawing, sketch, artwork, graphic
└── mural, graffiti, portrait, abstract
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `art` | painting, drawing, sculpture, mural | photo, selfie |
| `painting` | canvas, oil, watercolor, acrylic | drawing, sculpture |
| `sculpture` | statue, carving, figurine | painting |

---

## 🏛️ ARCHITECTURE

### Hierarchy
```
architecture
├── building → structure, edifice, construction
├── house → home, residence, cottage, villa, mansion, apartment
├── church → cathedral, chapel, temple, mosque, synagogue
├── castle → palace, fortress, citadel, manor
├── tower → skyscraper, spire, steeple, turret
└── bridge → overpass, viaduct
```

### Search Examples
| Search | Finds | Does NOT Find |
|--------|-------|---------------|
| `architecture` | building, house, church, castle, tower | furniture |
| `house` | home, cottage, villa, mansion | church, castle |
| `church` | cathedral, chapel, temple, mosque | house, castle |

---

## 📄 DOCUMENTS

### Hierarchy
```
document
├── paper, text, letter, note, form, certificate
├── screenshot → screen capture, screen shot
├── receipt → invoice, bill, ticket
├── book → magazine, newspaper, novel, textbook, reading
│   ├── newspaper → news, article, press
│   └── magazine → journal, publication
└── menu, ticket
```

---

## 🪑 FURNITURE & OBJECTS

### Hierarchy
```
furniture
├── chair → seat, stool, armchair
├── table → desk, counter, countertop
├── sofa → couch, loveseat, settee
├── bed → mattress, bunk bed, crib
└── drawer, wardrobe, closet, bench, ottoman

clothing
├── shirt → blouse, t-shirt, polo, jersey
├── pants → jeans, trousers, slacks, leggings
├── dress → gown, skirt, frock
├── jacket → coat, blazer, hoodie, sweater
├── shoes → sneakers, boots, sandals, heels, loafers, footwear
├── hat → cap, beanie, helmet, headwear
└── glasses → sunglasses, eyeglasses, spectacles, shades

jewelry → ring, necklace, bracelet, earring, watch, pendant, chain
└── watch → wristwatch, timepiece, clock
```

---

## 🌸 PLANTS

### Hierarchy
```
plant
├── flower → rose, tulip, daisy, sunflower, orchid, lily, blossom, petal, bloom
├── tree → oak, pine, palm, maple, forest, woods, branch, trunk
├── grass, bush, shrub, leaf, flora
└── garden → yard, lawn, backyard, greenhouse
```

---

## 🏠 ROOMS

### Hierarchy
```
room
├── bedroom → bed, sleep, pillow, mattress
├── bathroom → shower, bathtub, toilet, sink
├── kitchen → stove, oven, refrigerator, cooking, chef
├── living room
├── dining room
└── office → desk, computer, work, workspace
```

---

## 🧸 TOYS & GAMES

### Hierarchy
```
toy → doll, teddy bear, lego, puzzle, ball, stuffed animal, action figure
└── lego → blocks, bricks, building blocks

game → video game, board game, cards, gaming, console
```

---

## 😊 BODY PARTS

### Hierarchy
```
face → eyes, nose, mouth, smile, expression
├── eyes → eye, gaze, look
└── smile → grin, laugh, happy, smiling

hair → hairstyle, haircut, blonde, brunette, redhead
hand → hands, fingers, grip, holding
```

---

## 🚜 FARM

### Hierarchy
```
farm
├── barn → stable, farmhouse, silo
├── crop → wheat, corn, harvest, field
├── livestock → cattle, cow, pig, sheep, goat, chicken, poultry
└── field, tractor, harvest
```

---

## Known Issues / Future Improvements

1. **Fish ambiguity**: "fish" appears in both `pet` and `marine` - searching "pet" will find aquarium fish AND ocean fish
2. **Bird overlap**: Some birds could be pets OR wildlife (parrot vs eagle)
3. **Bike ambiguity**: Intentionally matches both bicycle and motorcycle
4. **Food containers**: "bottle", "cup", "glass" are in food but might match non-food photos
5. **Room vs Object**: Searching "bed" finds bedroom photos too - might be too broad

---

## How to Add New Terms

1. Find the appropriate category
2. Add to superclass if it's a broad term that should find many things
3. Add as subclass (own entry) if it needs specific variants
4. **Never** add upward links (subclass should not expand to siblings or superclass)

Example - adding "hamster":
```dart
// ✅ CORRECT: hamster is in pet's expansion list
'pet': ['dog', 'cat', 'hamster', ...],

// ❌ WRONG: Don't add 'pet' to hamster's expansion
'hamster': ['pet', 'rodent'],  // BAD - would find cats when searching hamster!

// ✅ CORRECT: Only close variants
'hamster': ['gerbil', 'guinea pig'],  // OK - similar rodents only
```
