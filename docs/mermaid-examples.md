# Mermaid Diagram Examples

A comprehensive gallery of Mermaid diagrams demonstrating all **33** diagram families supported natively in **Siren** via `pele_dart`: flowcharts, sequence diagrams, state diagrams, class diagrams, entity-relationship diagrams, Gantt charts, pie charts, Git graphs, user journeys, requirement diagrams, XY charts, quadrant charts, mindmaps, timelines, Sankey diagrams, packet diagrams, block diagrams, Kanban boards, C4 architecture diagrams (`C4Context`, `C4Component`), architecture diagrams, radar diagrams, treemap diagrams, Venn diagrams, railroad grammar diagrams (`railroad-ebnf-beta`, `railroad-beta`, `railroad-abnf-beta`, `railroad-peg-beta`), TreeView diagrams, Ishikawa diagrams, Cynefin diagrams, Wardley maps, event modeling diagrams, agentflow diagrams, use case diagrams, swimlane diagrams, and info diagrams.

---

## 1. Flowcharts & Graphs (`flowchart`, `graph`)

### Service Architecture Subgraphs

```mermaid
flowchart LR
  subgraph Client
    UI[Web app]
    Cache[(Local cache)]
  end
  subgraph Services
    API[API gateway]
    Auth[Auth service]
    Orders[Order service]
  end
  subgraph Storage
    DB[(Orders DB)]
  end
  UI --> API
  UI --> Cache
  API --> Auth
  API --> Orders
  Orders --> DB
  Auth -. token .-> UI
```

### Pure-Dart Rendering Pipeline

```mermaid
flowchart TD
  A([Mermaid text]) --> B{Supported?}
  B -- Yes --> C[Parse]
  B -- No --> H[Fall back]

  subgraph Pele
    C --> D[Layout]
    D --> E[Render]
  end

  E --> F[(SVG)]
  F -.-> G[Compile to Vector Graphics]
```

### Simple Left-Right Graph

```mermaid
graph LR
    A-->B
    A-->C
    B-->D
    C-->D
```

### Simple Top-Down Graph

```mermaid
graph TD
    A-->B
    A-->C
    B-->D
    C-->D
```

### Node Shapes & Link Variants

```mermaid
graph LR
    A[Square Rect] -- Link text --> B((Circle))
    A --> C(Round Rect)
    B --> D{Rhombus}
    C --> D
```

### Basic Decision Flowchart

```mermaid
graph TB
    A[Start] ==> B{Is it?}
    B -->|Yes| C[OK]
    C --> D[Rethink]
    D -.-> B
    B ---->|No| E[End]
```

### Troubleshooting Flowchart

```mermaid
graph TD
   A(Coffee machine <br>not working) --> B{Machine has power?}
   B -->|No| H(Plug in and turn on)
   B -->|Yes| C{Out of beans or water?} -->|Yes| G(Refill beans and water)
   C -->|No| D{Filter warning?} -->|Yes| I(Replace or clean filter)
   D -->|No| F(Send for repair)
```

### Flowchart with Hyperlinks

```mermaid
flowchart LR
    A-->B["B† (internal link)"]
    B-->C
    C-->D["D‡ (external link)"]
    click B "https://mermaid.js.org/syntax/flowchart.html#interaction"
    click D "https://mermaid.js.org/"
```

---

## 2. Sequence Diagrams (`sequenceDiagram`)

### Order Checkout & Payment Authorization

```mermaid
sequenceDiagram
  autonumber
  actor Customer
  participant Web as Web app
  participant API as API gateway
  participant Bank
  Customer->>Web: Place order
  Web->>API: POST /orders
  activate API
  API->>Bank: Authorize payment
  Bank-->>API: Approved
  API-->>Web: 201 Created
  deactivate API
  Web-->>Customer: Order confirmed
  Note over Customer,Bank: One order, one transaction
```

### Three-Way Handshake

```mermaid
sequenceDiagram
  participant c as Client
  participant s as Server

  c->>s: SYN
  note over c, s: SEQ1 = 100<br>ACK1 not set
  s->>c: SYN+ACK
  note over c, s: SEQ2 = 300<br>ACK2 = 100+1 = 101
  c->>s: ACK
  note over c, s: SEQ3 = 101<br>ACK3 = 300+1 = 301
```

### Loops, Alt, and Opt Blocks

```mermaid
sequenceDiagram
    loop Daily query
        Alice->>Bob: Hello Bob, how are you?
        alt is sick
            Bob->>Alice: Not so good :(
        else is well
            Bob->>Alice: Feeling fresh like a daisy
        end

        opt Extra response
            Bob->>Alice: Thanks for asking
        end
    end
```

### Parallel Service Notifications (`par` / `and`)

```mermaid
sequenceDiagram
    participant web as Web Browser
    participant blog as Blog Service
    participant account as Account Service
    participant mail as Mail Service
    participant db as Storage

    Note over web,db: The user must be logged in to submit blog posts
    web->>+account: Logs in using credentials
    account->>db: Query stored accounts
    db->>account: Respond with query result

    alt Credentials not found
        account->>web: Invalid credentials
    else Credentials found
        account->>-web: Successfully logged in

        Note over web,db: When the user is authenticated, they can now submit new posts
        web->>+blog: Submit new post
        blog->>db: Store post data

        par Notifications
            blog--)mail: Send mail to blog subscribers
            blog--)db: Store in-site notifications
        and Response
            blog-->>-web: Successfully posted
        end
    end
```

---

## 3. State Diagrams (`stateDiagram-v2`)

### Editorial Review Composite State

```mermaid
stateDiagram-v2
  [*] --> Draft
  Draft --> Submitted : submit
  state Review {
    [*] --> Screening
    Screening --> Decision
  }
  Submitted --> Review
  Review --> Published : approved
  Review --> Draft : rejected
  Published --> [*]
```

### Fork and Join State Diagram

```mermaid
stateDiagram-v2
    state fork_state <<fork>>
      [*] --> fork_state
      fork_state --> State2
      fork_state --> State3

      state join_state <<join>>
      State2 --> join_state
      State3 --> join_state
      join_state --> State4
      State4 --> [*]
```

### State Diagram with Notes

```mermaid
stateDiagram-v2
    State1: The state with a note
    note right of State1
        Important information! You can write
        notes.
    end note
    State1 --> State2
    note left of State2 : This is the note to the left.
```

### Shipment Status State Diagram (`direction LR`)

```mermaid
stateDiagram-v2
  direction LR
  [*] --> Initialed
  Initialed --> SellerSent
  SellerSent --> Transported
  Transported --> BuyerPicked
  BuyerPicked --> Delivered
  Delivered --> [*]

  BuyerPicked --> BuyerSent
  BuyerSent --> ReturnTransported
  ReturnTransported --> SellerPicked
  SellerPicked --> [*]

  Transported --> ReturnTransported: buyer doesn't pick up the item after 1 week
```

---

## 4. Class Diagrams (`classDiagram`)

### Namespace Hierarchy

```mermaid
---
config:
  class:
    hierarchicalNamespaces: false
---
classDiagram
    namespace Earth.Volcano.Summit {
        class Crater {
            +erupt()
        }
    }
    namespace Earth.Volcano.Slope {
        class LavaFlow {
            +buildLand()
        }
    }
    namespace Earth {
        class Hotspot {
            +meltRock()
        }
    }
    Hotspot --> Crater : feeds
    Hotspot --> LavaFlow : feeds
```

### Inheritance and Methods

```mermaid
classDiagram
    Animal <|-- Duck
    Animal <|-- Fish
    Animal <|-- Zebra
    Animal : +int age
    Animal : +String gender
    Animal: +isMammal()
    Animal: +mate()
    class Duck{
      +String beakColor
      +swim()
      +quack()
    }
    class Fish{
      -int sizeInFeet
      -canEat()
    }
    class Zebra{
      +bool is_wild
      +run()
    }
```

---

## 5. Entity Relationship Diagrams (`erDiagram`)

### Customer Orders & Products Schema

```mermaid
erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER ||--|{ LINE_ITEM : contains
  PRODUCT ||--o{ LINE_ITEM : "appears in"
  CUSTOMER {
    string name
    string email
  }
  ORDER {
    int id
    date placedAt
  }
  LINE_ITEM {
    int quantity
    float price
  }
  PRODUCT {
    string sku
    string title
  }
```

### E-Commerce Domain Relationships

```mermaid
erDiagram
    CUSTOMER }|..|{ DELIVERY-ADDRESS : has
    CUSTOMER ||--o{ ORDER : places
    CUSTOMER ||--o{ INVOICE : "liable for"
    DELIVERY-ADDRESS ||--o{ ORDER : receives
    INVOICE ||--|{ ORDER : covers
    ORDER ||--|{ ORDER-ITEM : includes
    PRODUCT-CATEGORY ||--|{ PRODUCT : contains
    PRODUCT ||--o{ ORDER-ITEM : "ordered in"
```

---

## 6. Gantt Charts (`gantt`)

### Multi-Team Project Schedule

```mermaid
gantt
    title Example Gantt diagram
    dateFormat YYYY-MM-DD
    section Team 1
    Research & requirements :done, a1, 2020-03-08, 2020-04-10
    Review & documentation  :after a1, 20d
    section Team 2
    Implementation          :crit, active, 2020-03-25, 20d
    Testing                 :crit, 20d
```

### Sequential Tasks with Excluded Date

```mermaid
gantt
    dateFormat YYYY-MM-DD
    title Adding GANTT diagram to mermaid
    excludes 2014-01-10

    section A section
    Completed task :done, des1, 2014-01-06, 2014-01-08
    Active task    :active, des2, 2014-01-09, 3d
    Future task    :des3, after des2, 5d
    Future task2   :des4, after des3, 5d
```

---

## 7. Pie Charts (`pie`)

### Crew Catch Breakdown

```mermaid
pie title Fish caught by the crew
    "ʻAhi" : 386
    "Mahimahi" : 85
    "Ono" : 15
```

### Volunteer Pet Adoptions

```mermaid
pie title Pets adopted by volunteers
    "Dogs" : 386
    "Cats" : 85
    "Rats" : 15
```

---

## 8. Git Graphs (`gitGraph`)

### Branches, Merge, and Cherry-Pick

```mermaid
gitGraph
    commit id: "ZERO"
    branch develop
    branch release
    commit id: "A"
    checkout main
    commit id: "ONE"
    checkout develop
    commit id: "B"
    checkout main
    merge develop id: "MERGE"
    commit id: "TWO"
    checkout release
    cherry-pick id: "MERGE" parent: "B"
    commit id: "THREE"
    checkout develop
    commit id: "C"
```

### Commit Tags and Highlights

```mermaid
gitGraph
    commit id: "init"
    branch feature
    checkout feature
    commit id: "feat-1"
    commit tag: "v0.1.0"
    checkout main
    commit type: HIGHLIGHT
    merge feature
    commit id: "release"
```

---

## 9. User Journey Diagrams (`journey`)

### Working Day Journey

```mermaid
journey
    title My working day
    section Go to work
      Make tea: 5: Me
      Go upstairs: 3: Me
      Do work: 1: Me, Cat
    section Go home
      Go downstairs: 5: Me
      Sit down: 5: Me
```

---

## 10. Requirement Diagrams (`requirementDiagram`)

### Checkout & Payment Functional Requirements

```mermaid
requirementDiagram
  requirement checkout_req {
    id: 1
    text: Orders must be payable online.
    risk: high
    verifymethod: test
  }
  functionalRequirement payment_req {
    id: 1.1
    text: Card payments must be authorized.
    risk: high
    verifymethod: test
  }
  element checkout_service {
    type: service
  }
  checkout_req - contains -> payment_req
  checkout_service - satisfies -> payment_req
```

---

## 11. XY Charts (`xychart`, `xychart-beta`)

### Monthly Ocean Temperature

```mermaid
xychart
    title "Ocean Temperature"
    x-axis [jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec]
    y-axis "Temperature (in °F)" 74 --> 82
    bar [76.3, 75.9, 76.0, 76.7, 77.8, 78.9, 79.9, 80.7, 81.1, 80.5, 79.1, 77.4]
    line [76.3, 75.9, 76.0, 76.7, 77.8, 78.9, 79.9, 80.7, 81.1, 80.5, 79.1, 77.4]
```

### Quarterly Sales Revenue

```mermaid
xychart-beta
    title "Quarterly Sales Revenue"
    x-axis [Q1, Q2, Q3, Q4]
    y-axis "Revenue (in $k)" 0 --> 120
    bar [45, 72, 88, 110]
    line [40, 68, 85, 105]
```

---

## 12. Quadrant Charts (`quadrantChart`)

### Campaign Reach vs. Engagement

```mermaid
quadrantChart
    title Reach and engagement of campaigns
    x-axis Low Reach --> High Reach
    y-axis Low Engagement --> High Engagement
    quadrant-1 We should expand
    quadrant-2 Need to promote
    quadrant-3 Re-evaluate
    quadrant-4 May be improved
    Campaign A: [0.3, 0.6]
    Campaign B: [0.45, 0.23]
    Campaign C: [0.57, 0.69]
    Campaign D: [0.78, 0.34]
    Campaign E: [0.40, 0.34]
    Campaign F: [0.35, 0.78]
```

---

## 13. Mindmaps (`mindmap`)

### Hawaiʻi History, Nature & Culture

```mermaid
mindmap
  root((Hawaiʻi))
    History
      Old legends
      ::icon(fa fa-book)
      Voyaging
        Polynesian navigators who sailed by the stars
    Nature
      Mountains<br/>and volcanoes
      Ocean life
        Reef
            Sea turtles
            Monk seals
            Parrotfish
    Culture
      Hula and lei
      ʻUkulele
```

### Siren Feature Hierarchy

```mermaid
mindmap
  root((Siren))
    Rendering
      CommonMark
      GitHub Alerts
      LaTeX Math
      Pure-Dart Mermaid
    Navigation
      Quick Open
      Outline View
      File Explorer
    Search
      Ripgrep Engine
      Regex Indexing
```

---

## 14. Timelines (`timeline`)

### Timeline of the Hawaiian Islands

```mermaid
timeline
    title Timeline of the Hawaiian Islands
    section Older islands
        Kauaʻi : 5 million years old, Canyons, Sea <br>cliffs
        Oʻahu : 3 million years old, Diamond Head, Surf breaks
        Molokaʻi : 2 million years old, Fishponds, Tall cliffs
    section Younger islands
        Maui : 1 million years old, Haleakalā, Whale watching
        Hawaiʻi : Still growing, Mauna Kea, Kīlauea
```

---

## 15. Sankey Diagrams (`sankey`, `sankey-beta`)

### Energy Grid Distribution Flow

```mermaid
---
config:
  sankey:
    showValues: false
    nodeWidth: 14
    nodePadding: 18
---
sankey

Solar,Electricity Grid,140
Wind,Electricity Grid,185
Hydro,Electricity Grid,95
Natural Gas,Electricity Grid,160
Natural Gas,District Heating,110
Electricity Grid,Homes,190
Electricity Grid,Industry,230
Electricity Grid,Electric Transport,95
Electricity Grid,Grid Losses,65
District Heating,Homes,70
District Heating,Industry,40
```

---

## 16. Packet Diagrams (`packet`, `packet-beta`)

### TCP Packet Header

```mermaid
---
title: "TCP Packet"
---
packet
0-15: "Source Port"
16-31: "Destination Port"
32-63: "Sequence Number"
64-95: "Acknowledgment Number"
96-99: "Data Offset"
100-105: "Reserved"
106: "URG"
107: "ACK"
108: "PSH"
109: "RST"
110: "SYN"
111: "FIN"
112-127: "Window"
128-143: "Checksum"
144-159: "Urgent Pointer"
160-191: "(Options and Padding)"
192-255: "Data (variable length)"
```

---

## 17. Block Diagrams (`block`, `block-beta`)

### Layered Database Block Diagram

```mermaid
block
columns 1
  db(("DB"))
  blockArrowId6<["&nbsp;&nbsp;&nbsp;"]>(down)
  block:ID
    A
    B["A wide one in the middle"]
    C
  end
  space
  D
  ID --> D
  C --> D
  style B fill:#969,stroke:#333,stroke-width:4px
```

---

## 18. Kanban Boards (`kanban`)

### Engineering Sprint Board with Ticket Metadata

```mermaid
---
config:
  kanban:
    ticketBaseUrl: 'https://mermaidchart.atlassian.net/browse/#TICKET#'
---
kanban
  Todo
    [Create Documentation]
    docs[Create Blog about the new diagram]
  [In progress]
    id6[Pure-Dart vector Mermaid rendering in Siren]
  id9[Ready for deploy]
    id8[Design grammar]@{ assigned: 'knsv' }
  id10[Ready for test]
    id4[Create parsing tests]@{ ticket: MC-2038, assigned: 'K.Sveidqvist', priority: 'High' }
    id66[Verify dark and light palettes]@{ priority: 'Low', assigned: 'tkinnis' }
  id11[Done]
    id5[Remove WebView dependency]
    id3[Proportional font scaling]@{ ticket: MC-2037, assigned: 'tkinnis', priority: 'High' }
```

---

## 19. C4 Architecture Diagrams (`C4Context`, `C4Component`)

### System Context Diagram

```mermaid
C4Context
    title System Context diagram for Internet Banking System
    Person(customerA, "Banking Customer A", "A customer of the bank.")
    System(SystemAA, "Internet Banking System", "Allows customers to view information about their bank accounts, and make payments.")
    System_Ext(SystemE, "Mainframe Banking System", "Stores all of the core banking information about customers, accounts, transactions, etc.")
    Rel(customerA, SystemAA, "Uses")
    Rel(SystemAA, SystemE, "Uses")
```

### API Application Component Diagram

```mermaid
C4Component
    title Component diagram for Internet Banking System - API Application

    Container(spa, "Single Page Application", "JavaScript and Angular", "Provides all the internet banking functionality to customers via their web browser.")
    Container(ma, "Mobile App", "Flutter", "Provides internet banking functionality to customers via their mobile device.")
    ContainerDb(db, "Database", "Relational Database Schema", "Stores user registration information, hashed authentication credentials, access logs, etc.")
    System_Ext(mbs, "Mainframe Banking System", "Stores all of the core banking information about customers, accounts, transactions, etc.")

    Container_Boundary(api, "API Application") {
        Component(sign, "Sign In Controller", "MVC Rest Controller", "Allows users to sign in to the internet banking system")
        Component(accounts, "Accounts Summary Controller", "MVC Rest Controller", "Provides customers with a summary of their bank accounts")
        Component(security, "Security Component", "Spring Bean", "Provides functionality related to signing in, changing passwords, etc.")
        Component(mbsfacade, "Mainframe Banking System Facade", "Spring Bean", "A facade onto the mainframe banking system.")

        Rel(sign, security, "Uses")
        Rel(accounts, mbsfacade, "Uses")
        Rel(security, db, "Read & write to", "JDBC")
        Rel(mbsfacade, mbs, "Uses", "XML/HTTPS")
    }

    Rel_Back(spa, sign, "Uses", "JSON/HTTPS")
    Rel(spa, accounts, "Uses", "JSON/HTTPS")
    Rel(ma, sign, "Uses", "JSON/HTTPS")
    Rel(ma, accounts, "Uses", "JSON/HTTPS")
```

---

## 20. Architecture Diagrams (`architecture-beta`)

### Cloud Service Topology

```mermaid
architecture-beta
    group api(cloud)[API]

    service db(database)[Database] in api
    service disk1(disk)[Storage] in api
    service disk2(disk)[Storage] in api
    service server(server)[Server] in api

    db:L -- R:server
    disk1:T -- B:server
    disk2:T -- B:db
```

---

## 21. Radar Diagrams (`radar-beta`)

### Multi-Axis Grades Comparison

```mermaid
---
title: "Grades"
---
radar-beta
  axis m["Math"], s["Science"], e["English"]
  axis h["History"], g["Geography"], a["Art"]
  curve a["Alice"]{85, 90, 80, 70, 75, 90}
  curve b["Bob"]{70, 75, 85, 80, 90, 85}

  max 100
  min 0
```

---

## 22. Treemap Diagrams (`treemap-beta`)

### Product Catalog Hierarchy

```mermaid
treemap-beta
"Products"
    "Electronics"
        "Phones": 50
        "Computers": 30
        "Accessories": 20
    "Clothing"
        "Men's": 40
        "Women's": 40
```

---

## 23. Venn Diagrams (`venn-beta`)

### Three-Set Feature Overlap

```mermaid
venn-beta
  title What makes a good feature
  set Desirable
  set Feasible
  set Viable
  union Desirable,Feasible["Buildable"]
  union Feasible,Viable["Sustainable"]
  union Desirable,Viable["Marketable"]
  union Desirable,Feasible,Viable["Ship it"]
```

---

## 24. Railroad Diagrams (`railroad-ebnf-beta`, `railroad-beta`, `railroad-abnf-beta`, `railroad-peg-beta`)

### Arithmetic Expression Grammar (`railroad-ebnf-beta`)

```mermaid
railroad-ebnf-beta
title "Arithmetic Expression Grammar"

expression = term ( ( "+" | "-" ) term )* ;
term = factor ( ( "*" | "/" ) factor )* ;
factor = number | "(" expression ")" ;
number = digit+ ;
digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
```

### Select Clause Combinator Grammar (`railroad-beta`)

```mermaid
railroad-beta
    select = sequence(
        terminal("SELECT"),
        nonterminal("column"),
        zeroOrMore(sequence(terminal(","), nonterminal("column"))),
        terminal("FROM"),
        nonterminal("table"),
        optional(sequence(terminal("WHERE"), nonterminal("predicate")))
    );
```

### ABNF Rule Grammar (`railroad-abnf-beta`)

```mermaid
railroad-abnf-beta
    header = field-name ":" [ field-value ] CRLF;
```

### PEG Rule Grammar (`railroad-peg-beta`)

```mermaid
railroad-peg-beta
    pair <- key ":" value ("," key ":" value)*;
```

---

## 25. TreeView Diagrams (`treeView-beta`)

### Highlighted Project Tree with Icons & Annotations

```mermaid
treeView-beta
├── src/
│   ├── App.tsx :::highlight icon(logos:react) ## main component
│   └── index.ts ## entry point
├── .env ## environment variables
├── Dockerfile
└── package.json
```

---

## 26. Ishikawa Diagrams (`ishikawa-beta`)

### Multi-Level Cause & Effect Fishbone

```mermaid
ishikawa-beta
    Blurry Photo
    Process
        Out of focus
        Shutter speed too slow
        Protective film not removed
        Beautification filter applied
    User
        Shaky hands
    Equipment
        LENS
            Inappropriate lens
            Damaged lens
            Dirty lens
        SENSOR
            Damaged sensor
            Dirty sensor
    Environment
        Subject moved too quickly
        Too dark
```

---

## 27. Cynefin Diagrams (`cynefin-beta`)

### Five-Domain Incident Response Framework

```mermaid
cynefin-beta
  title Incident Response

  complex
    "Investigate root cause"
    "Run chaos experiment"

  complicated
    "Analyze performance data"
    "Expert review needed"

  clear
    "Restart service"
    "Apply known fix"

  chaotic
    "Page on-call immediately"

  confusion
    "Unknown failure mode"

  chaotic --> complex : "stabilize"
  complex --> complicated : "codify"
```

---

## 28. Wardley Maps (`wardley-beta`)

### Tea Shop Value Chain with Evolution & Notes

```mermaid
wardley-beta
title Tea Shop Value Chain

anchor Business [0.95, 0.63]
component Cup of Tea [0.79, 0.61]
component Tea [0.63, 0.81]
component Hot Water [0.52, 0.80]
component Kettle [0.43, 0.35]
component Power [0.10, 0.70]

Business -> Cup of Tea
Cup of Tea -> Tea
Cup of Tea -> Hot Water
Hot Water -> Kettle
Kettle -> Power

evolve Kettle 0.62
evolve Power 0.89

note "Standardizing power allows Kettles to evolve faster" [0.30, 0.49]
```

---

## 29. Event Modeling Diagrams (`eventmodeling`)

### Shopping Cart Command, Event & Read-Model Slice

```mermaid
eventmodeling
    tf 01 ui CartView
    tf 02 cmd AddItem ->> 01
    tf 03 evt ItemAdded ->> 02
    tf 04 rmo CartSummary ->> 03
```

---

## 30. Agentflow Diagrams (`agentflow-beta`)

### Multi-Agent Drafting & Review Pipeline

```mermaid
agentflow-beta TB
  brief["Release brief"]@{ shape: input }
  flow writer["Drafting Agent"]
    draft["Draft the notes"]@{ shape: task }
    lookup["changelog_search"]@{ shape: tool }
    guide["Tone of voice"]@{ shape: refdoc }
    draft --> lookup
    draft -.- guide
  end
  flow reviewer["Review Agent"]
    check["Check the claims"]@{ shape: task }
    ok["Accurate?"]@{ shape: decision }
    check --> ok
  end
  publish["Publish"]@{ shape: action }
  brief --> writer
  writer --> reviewer
  ok --> publish
```

---

## 31. Use Case Diagrams (`usecase-beta`)

### Storefront & Fulfillment System Boundaries

```mermaid
usecase-beta
direction LR
actor Customer
actor Support
systemBoundary Storefront
  Browse("Browse catalog")
  Checkout("Checkout")
end
systemBoundary Fulfilment
  Track("Track delivery")
end
Customer --> Browse
Customer --> Checkout
Customer --> Track
Support --> Track
Checkout ..> : include Browse
```

---

## 32. Swimlane Diagrams (`swimlane-beta`)

### Cross-Department Order Fulfillment

```mermaid
swimlane-beta LR
  subgraph Customer
    Browse[Browse catalog]
    Pay[Pay]
  end
  subgraph Warehouse
    Pick[Pick items]
    Ship[Ship order]
  end
  subgraph Finance
    Invoice[Raise invoice]
  end
  Browse --> Pay
  Pay --> Pick
  Pick --> Ship
  Pay --> Invoice
```

---

## 33. Info Diagrams (`info`)

### Package Version Info

```mermaid
info
```
