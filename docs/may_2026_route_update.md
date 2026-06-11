# May 2026 Bus Routes, Buses, and Drivers Seeding Documentation

This document explains the process, heuristics, and architecture behind the **May 2026 Bus Routes update** populated in the MongoDB database for **Sagar Group of Institutions, Ratibad, Bhopal**.

---

## 1. Visual OCR Heuristics & Extraction

Since `Bus Route And schedule collage.pdf` consisted of scanned paper sheets rather than selectable digital text, we employed **EasyOCR** (CPU-based neural network model) to scan and extract raw visual blocks on all 30 pages. The visual raw blocks were parsed and resolved using a robust, custom parsing pipeline addressing the following visual anomalies:

* **Multi-Table Segmentation**: Programmatically partitioned split pages featuring multiple tables (e.g., Page 20 with Buses T-5 and T-6, and Page 29 with Buses 12 and 21) based on vehicle and driver headers to prevent cross-contamination.
* **Timing Normalization**: Standardized timing formats from various notations (`8.10 AM`, `830 AM`, `8.30 AM`, `6.50`, etc.) to strict `HH:MM` format.
* **Stop Name Lookback Skipping**: Built lookback time verification heuristics to prevent timetamps from being recognized as stop names.
* **Split-Page Route Merger**: Successfully merged routes that were split across pages (e.g., Bus T-6, whose header was on Page 20 and stops/timings were on Page 21) into a single, unified database route.
* **Sanitization**: Removed trailing hyphens, brackets, and underscores from stop names (e.g., `Ratibad Campus_` to `Ratibad Campus`, `Neelbad )` to `Neelbad`).

---

## 2. Seeding & Database Linking Structure

The database seeding is performed via the script in [seed_real_routes.js](file:///d:/BUS%20TRACKING/SISTecChalo/backend/seed_real_routes.js).

### Data Integrity Features:
1. **Bidirectional Document Linking**: 
   * Each driver's document (`assignedBus`) points to the correct Bus ID.
   * Each bus document's (`driverId`) points back to that same Driver ID.
2. **Argon2 Secure Encryption**: Driver passwords are encrypted using **Argon2** (default password `123456`).
3. **Unique Username Resolution**: To avoid unique username constraint crashes in MongoDB due to multiple shifts/trips on the same bus numbers (such as Bus 18, Bus 04, and Private Vehicles), sequential suffixes are appended dynamically (e.g., `driver18` and `driver182` for Bus 18, and `driverprivatevehicle`, `driverprivatevehicle2`, `driverprivatevehicle3` for Private Vehicles).
4. **Clean Geographic Data**: Pre-seeded all routes to terminate at the **Ratibad Campus (lat: `23.1270`, lng: `77.3494`)** with empty coordinates arrays for the polylines, which should be updated either via live manager drawing or live-tracking coordinates upload.

---

## 3. Verification

An automated verification script has been added to [verify_db_counts.js](file:///d:/BUS%20TRACKING/SISTecChalo/backend/verify_db_counts.js). Running it connects to the active MongoDB instance and performs count validations and bidirectional link audits.

```bash
cd SISTecChalo/backend
node verify_db_counts.js
```

### Confirmed Database Counts:
* **Routes**: 30 / 30 (✅ Match)
* **Buses**: 30 / 30 (✅ Match)
* **Drivers**: 30 / 30 (✅ Match)
* **Integrity Audit**: 30 / 30 buses linked correctly back and forth.

---

## 4. Seeded Driver Login Credentials

All driver accounts have the default password **`123456`**. 

| Driver Username | Driver Name | Bus / Shift |
| :--- | :--- | :--- |
| `driver01` | Ghanshyam Nagar | MP04 PA 3496 (Bus 01) |
| `driver03` | Unknown Driver | N/A (Bus 03) |
| `driver04` | Mukesh Shisodiya | MP04 PA 3504 (Bus 04 - Trip 1) |
| `driver042` | Mukesh Shiodiya | MP04 PA 3504 (Bus 04 - Trip 2) |
| `driver05` | Babloo Meena | MP04 PA 3510 (Bus 05) |
| `driver06` | Unknown Driver | N/A (Bus 06) |
| `driver07` | Unknown Driver | N/A (Bus 07) |
| `driver08` | Rahul Verma | MP04 YR 3428 (Bus 08) |
| `driver09` | Satish Tomar | N/A (Bus 09) |
| `driver11` | Tulsi Das | N/A (Bus 11) |
| `driver12` | Arjun Maran | MP04 PA 3521 (Bus 12) |
| `driver13` | Unknown Driver | MP04 PA 2288 (Bus 13) |
| `driver14` | RajeshPrajapati | N/A (Bus 14) |
| `driver15` | Unknown Driver | MP04 PA 2289 (Bus 15) |
| `driver16` | Rajesh Shisodiya | MP04 PA 2515 (Bus 16) |
| `driver18` | Mohmmad | MP04 PA 3428 (Bus 18 - Trip 1) |
| `driver182` | Mohmad | MP04 PA 3428 (Bus 18 - Trip 2) |
| `driver19` | Dinesh Jatav | MP04 PA 1543 (Bus 19) |
| `driver21` | Ahad Ali | MP04 PA 9712 (Bus 21) |
| `driver23` | Sandeep Vishvkarma | MP04 PA 1503 (Bus 23) |
| `driver24` | Unknown Driver | N/A (Bus 24) |
| `driver26` | Unknown Driver | MP04 YR 4318 (Bus 26) |
| `driver27` | Unknown Driver | MP04 YR 3427 (Bus 27) |
| `driver28` | Krishna Verma | MP04 YR 4386 (Bus 28) |
| `driverprivatevehicle` | Gopal | MP04 1141 (Private Vehicle 1) |
| `driverprivatevehicle2` | Sahrukh | MP04 PA 7220 (Private Vehicle 2) |
| `driverprivatevehicle3` | Farheed Bhai | MP04 PA 2127 (Private Vehicle 3) |
| `drivert4` | Unknown Driver | MP04 PA 4443 (Bus T-4) |
| `drivert5` | Rahul Vishvkarma | MP04 PA 4442 (Bus T-5) |
| `drivert6` | Jitendra Prajapati | N/A (Bus T-6) |

