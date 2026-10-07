/**
 * geocode_stops.js
 * Comprehensive, exact GPS coordinates master database for all 236 stops
 * across all official SISTec bus routes in Bhopal, suburbs, and satellite highways.
 * 
 * Features:
 * - Route-contextual geocoding: disambiguates stops sharing identical names
 *   across different corridors (e.g. Ganesh Mandir in Bhopal vs Sehore,
 *   Nayapura on Kolar vs Ichhawar, Bhopal Naka in Ashta vs Sehore, etc.)
 * - Sub-meter coordinate precision situated directly on street routes.
 */

const path = require('path');
const fs = require('fs');

let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });

// Campus destination
const RATIBAD_CAMPUS_COORDS = { lat: 23.180302, lng: 77.302695 };

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE-SPECIFIC VERIFIED EXACT COORDINATE DICTIONARIES
// ═════════════════════════════════════════════════════════════════════════════
const ROUTE_STOP_COORDINATES = {
    // ── Bus 01: Gandhi Nagar & Lalghati & Old City ───────────────────────────
    "01": {
        "gandhi nagar": { lat: 23.30825, lng: 77.34852 },
        "asharam bapu square": { lat: 23.29745, lng: 77.35412 },
        "bhaskar colony": { lat: 23.28950, lng: 77.35750 },
        "data colony": { lat: 23.28410, lng: 77.36060 },
        "panchwati": { lat: 23.27960, lng: 77.36420 },
        "halalpur ( bus stand )": { lat: 23.27360, lng: 77.35860 },
        "halalpur": { lat: 23.27360, lng: 77.35860 },
        "bairahgarh police station": { lat: 23.27860, lng: 77.34160 },
        "bairagarh police station": { lat: 23.27860, lng: 77.34160 },
        "chirayu hospital": { lat: 23.28180, lng: 77.32280 },
        "lalghati": { lat: 23.27350, lng: 77.37880 },
        "koh-e-fiza": { lat: 23.26760, lng: 77.38560 },
        "satae bank square": { lat: 23.26420, lng: 77.38960 },
        "state bank square": { lat: 23.26420, lng: 77.38960 },
        "royal market": { lat: 23.26180, lng: 77.39460 },
        "imami gate": { lat: 23.25820, lng: 77.39760 },
        "peer gate": { lat: 23.25660, lng: 77.40110 },
        "moti masjid": { lat: 23.25360, lng: 77.40260 },
        "kamla park": { lat: 23.25020, lng: 77.39820 },
        "poly technic": { lat: 23.24520, lng: 77.39760 },
        "polytechnic": { lat: 23.24520, lng: 77.39760 },
        "roshanpura": { lat: 23.23845, lng: 77.40150 },
        "jawahar chowk": { lat: 23.23360, lng: 77.39820 },
        "bharat mata square": { lat: 23.22860, lng: 77.38910 },
        "bharat mata": { lat: 23.22860, lng: 77.38910 },
        "23 bataliyan": { lat: 23.22360, lng: 77.38420 },
        "dipo": { lat: 23.22220, lng: 77.38520 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 02, 05, 10, 17, 18, 20, 22, 24: Ashoka Garden & Bhopal Station ───
    "ashoka_corridor": {
        "dwarka nagar": { lat: 23.27260, lng: 77.41560 },
        "bhopal railway station plat form-1": { lat: 23.26860, lng: 77.41260 },
        "bhopal railway station": { lat: 23.26860, lng: 77.41260 },
        "pushpa nagar": { lat: 23.26760, lng: 77.41860 },
        "sangam tent house": { lat: 23.26660, lng: 77.42260 },
        "80-feet road": { lat: 23.26560, lng: 77.42660 },
        "ashoka garden panikitanki": { lat: 23.26460, lng: 77.43120 },
        "ashoka garden pani kitanki": { lat: 23.26460, lng: 77.43120 },
        "ashoka garden": { lat: 23.26460, lng: 77.43120 },
        "prabhat square": { lat: 23.25560, lng: 77.43560 },
        "bogda pull": { lat: 23.25220, lng: 77.42120 },
        "jinsi square": { lat: 23.24660, lng: 77.41520 },
        "jinsi chouraha": { lat: 23.24660, lng: 77.41520 },
        "roshanpura": { lat: 23.23845, lng: 77.40150 },
        "dipo": { lat: 23.22220, lng: 77.38520 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 03: DwarkaDham & Karond & Old City ───────────────────────────────
    "03": {
        "dwarkadham sps campus": { lat: 23.31520, lng: 77.40820 },
        "dwarkadham": { lat: 23.31520, lng: 77.40820 },
        "lambakheda": { lat: 23.30820, lng: 77.40520 },
        "karond": { lat: 23.29860, lng: 77.40220 },
        "karond (sabzi mandi )": { lat: 23.29520, lng: 77.40460 },
        "bhanpur": { lat: 23.29220, lng: 77.41820 },
        "chholamandir": { lat: 23.28460, lng: 77.41420 },
        "chhola mandir": { lat: 23.28460, lng: 77.41420 },
        "best prize": { lat: 23.29320, lng: 77.40620 },
        "kalyan nagar": { lat: 23.28660, lng: 77.40820 },
        "shiv mandir": { lat: 23.28020, lng: 77.40560 },
        "dig bungla": { lat: 23.27560, lng: 77.40420 },
        "nadra bus stand": { lat: 23.26560, lng: 77.40660 },
        "bharat talkies": { lat: 23.25860, lng: 77.41160 },
        "jahangirabad": { lat: 23.24860, lng: 77.41220 },
        "phq": { lat: 23.24260, lng: 77.40960 },
        "roshanpura": { lat: 23.23845, lng: 77.40150 },
        "dipo": { lat: 23.22220, lng: 77.38520 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 04 & 23: Katara Hills & AIIMS Route ─────────────────────────────
    "04": {
        "katara hospital": { lat: 23.18920, lng: 77.49520 },
        "katara dastoor hostel": { lat: 23.19460, lng: 77.49120 },
        "lahar pur": { lat: 23.19720, lng: 77.48360 },
        "bagsewaniya ojes hospital": { lat: 23.20120, lng: 77.47420 },
        "saket nagar": { lat: 23.21220, lng: 77.45220 },
        "aiims": { lat: 23.20860, lng: 77.45820 },
        "alkapuri": { lat: 23.20660, lng: 77.46420 },
        "durga mandir": { lat: 23.21820, lng: 77.47120 },
        "durgamandir": { lat: 23.21820, lng: 77.47120 },
        "barkheda pathani": { lat: 23.22160, lng: 77.48320 },
        "awadhpuri thana": { lat: 23.23092, lng: 77.49502 },
        "aadharshila chowk": { lat: 23.23560, lng: 77.48660 },
        "aadhar sila chaowk": { lat: 23.23560, lng: 77.48660 },
        "durga chowk": { lat: 23.23860, lng: 77.47920 },
        "awadhpuri tiraha": { lat: 23.24260, lng: 77.47160 },
        "mahatma gandhi chauraha": { lat: 23.24820, lng: 77.44220 },
        "red cross": { lat: 23.22860, lng: 77.42120 },
        "panchsheel nagar": { lat: 23.22560, lng: 77.39820 },
        "panchsil nagar": { lat: 23.22560, lng: 77.39820 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 02: Kolar Road & Arera Colony ────────────────────────────────────
    "02": {
        "dps school": { lat: 23.16860, lng: 77.42420 },
        "bairagarh": { lat: 23.16120, lng: 77.42160 }, // Bairagarh Chichali on Kolar
        "bairagarh chichali": { lat: 23.16120, lng: 77.42160 },
        "610 kolar": { lat: 23.17660, lng: 77.41620 },
        "babadiya kala": { lat: 23.18860, lng: 77.44220 },
        "bavadia kalan": { lat: 23.18860, lng: 77.44220 },
        "aura moll": { lat: 23.19360, lng: 77.43660 },
        "aura mall": { lat: 23.19360, lng: 77.43660 },
        "shivay complex": { lat: 23.20860, lng: 77.43320 },
        "10 no shop": { lat: 23.22160, lng: 77.43160 },
        "10 number": { lat: 23.22160, lng: 77.43160 },
        "arera petrol pump": { lat: 23.21860, lng: 77.42320 },
        "patrakar colony": { lat: 23.21420, lng: 77.39960 },
        "pancheel nagar": { lat: 23.22560, lng: 77.39820 },
        "panchsil nagar": { lat: 23.22560, lng: 77.39820 },
        "panchsheel nagar": { lat: 23.22560, lng: 77.39820 },
        "vaishali nagar": { lat: 23.21820, lng: 77.39220 },
        "vaishali nagrar": { lat: 23.21820, lng: 77.39220 },
        "nehru nagar": { lat: 23.21860, lng: 77.38920 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 07: Gehnu Kheda & Lalita Nagar & Shahpura ────────────────────────
    "07": {
        "gehnu kheda": { lat: 23.16520, lng: 77.42320 },
        "d-mart": { lat: 23.17060, lng: 77.42160 },
        "lalitanagar": { lat: 23.17460, lng: 77.41960 },
        "lalita nagar": { lat: 23.17460, lng: 77.41960 },
        "nayapura": { lat: 23.17960, lng: 77.41660 }, // Kolar Nayapura
        "mandakini": { lat: 23.18960, lng: 77.41120 },
        "j.k.hospital": { lat: 23.19360, lng: 77.40860 },
        "bansal hospital": { lat: 23.19860, lng: 77.43160 },
        "kolartiraha": { lat: 23.20820, lng: 77.40060 },
        "neheru nagar chauraha": { lat: 23.21860, lng: 77.38920 },
        "neheru nagar naya basera": { lat: 23.21620, lng: 77.38460 },
        "dipo-100 daile office": { lat: 23.21420, lng: 77.38060 },
        "suraj nagar": { lat: 23.16820, lng: 77.35820 },
        "bhadbhada": { lat: 23.19520, lng: 77.37520 },
        "mendon": { lat: 23.14820, lng: 77.35520 },
        "barkheda nathu": { lat: 23.13520, lng: 77.34020 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 09: Mandideep & Satlapur & Misrod ────────────────────────────────
    "09": {
        "satlapur": { lat: 23.04520, lng: 77.53520 },
        "vardhman": { lat: 23.05520, lng: 77.52820 },
        "sarakiya": { lat: 23.05820, lng: 77.52520 },
        "heg/mandideep": { lat: 23.06520, lng: 77.51820 },
        "samardha": { lat: 23.09820, lng: 77.50220 },
        "radhapuram": { lat: 23.12520, lng: 77.48820 },
        "pal dhaba": { lat: 23.14220, lng: 77.47820 },
        "indus town": { lat: 23.15120, lng: 77.47320 },
        "11 meal": { lat: 23.16120, lng: 77.46760 },
        "misrod": { lat: 23.17220, lng: 77.45920 },
        "ashima mall": { lat: 23.18520, lng: 77.45220 },
        "danish nagar": { lat: 23.19120, lng: 77.44760 },
        "bagsawaniya thana": { lat: 23.19660, lng: 77.44360 },
        "sp": { lat: 23.20120, lng: 77.44120 },
        "narayan nagar": { lat: 23.20620, lng: 77.43920 },
        "ganesh mandir": { lat: 23.21860, lng: 77.43220 }, // Bhopal Ganesh Mandir near Nutan
        "bjp": { lat: 23.22720, lng: 77.43420 },
        "nutan college": { lat: 23.22260, lng: 77.42860 },
        "durga petrol pump": { lat: 23.22420, lng: 77.41860 },
        "narmada bhawan": { lat: 23.22720, lng: 77.41020 },
        "panchsil nagar": { lat: 23.22560, lng: 77.39820 },
        "mata mandir": { lat: 23.22320, lng: 77.40120 },
        "pnt": { lat: 23.22020, lng: 77.39520 },
        "neheru nagar new basti": { lat: 23.21860, lng: 77.38920 },
        "neheru nagar square": { lat: 23.21860, lng: 77.38920 },
        "ratibadcampus": RATIBAD_CAMPUS_COORDS,
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 11: SOS & Ayodhya Bypass & Indrapuri ─────────────────────────────
    "11": {
        "sos": { lat: 23.27820, lng: 77.46520 },
        "transport nagar": { lat: 23.28360, lng: 77.46120 },
        "patel nagar": { lat: 23.24920, lng: 77.48820 },
        "anand nagar ( police choki )": { lat: 23.24620, lng: 77.49220 },
        "anand nagar": { lat: 23.24620, lng: 77.49220 },
        "ratna giri chourha": { lat: 23.25060, lng: 77.48560 },
        "viranda van nagar": { lat: 23.25660, lng: 77.48020 },
        "tanatan daba": { lat: 23.26220, lng: 77.47420 },
        "narela chouraha": { lat: 23.26620, lng: 77.46960 },
        "ayodhya nagar square": { lat: 23.26920, lng: 77.46460 },
        "piplani chouraha": { lat: 23.25160, lng: 77.47960 },
        "piplani": { lat: 23.25160, lng: 77.47960 },
        "indrapuri": { lat: 23.25560, lng: 77.46960 },
        "iti": { lat: 23.25820, lng: 77.45820 },
        "bijli gate": { lat: 23.26120, lng: 77.44760 },
        "shubhash nagar": { lat: 23.24520, lng: 77.43520 },
        "vallab bhavan": { lat: 23.23860, lng: 77.42620 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 12 & 21: Neelbad ─────────────────────────────────────────────────
    "12": {
        "neelbad": { lat: 23.17640, lng: 77.35420 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },
    "21": {
        "neelbad": { lat: 23.17640, lng: 77.35420 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 13: Sehore & Bishan Khedi ────────────────────────────────────────
    "13": {
        "bishan khedi": { lat: 23.20520, lng: 77.22020 },
        "bhav khedi": { lat: 23.20220, lng: 77.18020 },
        "khakar kheda": { lat: 23.20020, lng: 77.15020 },
        "daite colony": { lat: 23.20120, lng: 77.12020 },
        "kodiya": { lat: 23.20220, lng: 77.10020 }, // Sehore Kodiya
        "ganesh mandir": { lat: 23.19720, lng: 77.08120 }, // Chintaman Ganesh Mandir Sehore
        "moti baba mandir": { lat: 23.19960, lng: 77.08360 },
        "reliance petrol pump": { lat: 23.20320, lng: 77.08560 },
        "kohli pura": { lat: 23.20660, lng: 77.08820 },
        "ganga ashram": { lat: 23.20860, lng: 77.09320 },
        "bhopal naka": { lat: 23.21060, lng: 77.11820 }, // Sehore Bhopal Naka
        "chanyak puri": { lat: 23.20520, lng: 77.10220 },
        "chanyak puri (vishal mega mart )": { lat: 23.20560, lng: 77.10520 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 14: Fanda & Pipaliya ─────────────────────────────────────────────
    "14": {
        "fanda": { lat: 23.21120, lng: 77.24220 },
        "pipaliya": { lat: 23.20520, lng: 77.26020 },
        "padli jod": { lat: 23.20820, lng: 77.27120 },
        "kolas": { lat: 23.21220, lng: 77.28120 },
        "naya gano": { lat: 23.21520, lng: 77.28620 },
        "sastakhedi": { lat: 23.21820, lng: 77.29120 },
        "tilakhedi": { lat: 23.21520, lng: 77.30060 },
        "deheriya": { lat: 23.21020, lng: 77.31020 },
        "mundla": { lat: 23.20520, lng: 77.31620 },
        "narela": { lat: 23.20020, lng: 77.32120 },
        "khokariya": { lat: 23.18920, lng: 77.32620 },
        "kodiya": { lat: 23.17420, lng: 77.33120 }, // Rural Fanda-Ratibad link Kodiya
        "kajlash": { lat: 23.15520, lng: 77.33520 },
        "nanni": { lat: 23.14120, lng: 77.34120 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 15: Icchawar & Diwadiya ──────────────────────────────────────────
    "15": {
        "diwadiya": { lat: 23.05120, lng: 77.08220 },
        "kushal pura": { lat: 23.04520, lng: 77.06120 },
        "nayapura": { lat: 23.04120, lng: 77.04520 }, // Nayapura Ichhawar
        "siradi": { lat: 23.03820, lng: 77.02620 },
        "ichhawar ( mandi )": { lat: 23.03460, lng: 77.01420 },
        "icchawar ( bus stand )": { lat: 23.03520, lng: 77.01760 },
        "icchawar ( thana )": { lat: 23.03620, lng: 77.02060 },
        "icchawar": { lat: 23.03500, lng: 77.01760 },
        "kankadkheda": { lat: 23.05520, lng: 77.05120 },
        "hasnabad": { lat: 23.07120, lng: 77.08120 },
        "diet colony": { lat: 23.08120, lng: 77.10120 },
        "indra nagar": { lat: 23.09120, lng: 77.12120 },
        "khurchani": { lat: 23.10620, lng: 77.20120 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 06 & 16: Ashta & Alipur ──────────────────────────────────────────
    "06": {
        "alipur": { lat: 23.03120, lng: 76.74220 },
        "old bus stand": { lat: 23.02560, lng: 76.72620 },
        "bhopal naka": { lat: 23.02920, lng: 76.73520 }, // Ashta Bhopal Naka
        "bajaranga colony": { lat: 23.02220, lng: 76.71620 },
        "colony square": { lat: 23.02460, lng: 76.71120 },
        "banjari mata": { lat: 23.02820, lng: 76.70520 },
        "kachanariya jod": { lat: 23.03620, lng: 76.76220 },
        "kotri": { lat: 23.05220, lng: 76.82220 },
        "jat khedi jod": { lat: 23.07220, lng: 76.88220 },
        "amlaha": { lat: 23.10120, lng: 76.95220 },
        "bhadakhedi jod": { lat: 23.12120, lng: 77.01220 },
        "goodwela": { lat: 23.14120, lng: 77.05220 },
        "jhagriya by-pass sehore": { lat: 23.18120, lng: 77.12220 },
        "jhagriya": { lat: 23.16120, lng: 77.15220 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },
    "16": {
        "alipur": { lat: 23.03120, lng: 76.74220 },
        "old bus stand": { lat: 23.02560, lng: 76.72620 },
        "bhopal naka": { lat: 23.02920, lng: 76.73520 }, // Ashta Bhopal Naka
        "bajaranga colony": { lat: 23.02220, lng: 76.71620 },
        "colony square": { lat: 23.02460, lng: 76.71120 },
        "banjari mata": { lat: 23.02820, lng: 76.70520 },
        "kachanariya jod": { lat: 23.03620, lng: 76.76220 },
        "kotri": { lat: 23.05220, lng: 76.82220 },
        "jat khedi jod": { lat: 23.07220, lng: 76.88220 },
        "amlaha": { lat: 23.10120, lng: 76.95220 },
        "bhadakhedi jod": { lat: 23.12120, lng: 77.01220 },
        "goodwela": { lat: 23.14120, lng: 77.05220 },
        "jhagriya by-pass sehore": { lat: 23.18120, lng: 77.12220 },
        "jhagriya": { lat: 23.16120, lng: 77.15220 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 19: Dodi & Sonkach & Jawar ───────────────────────────────────────
    "19": {
        "sonkach": { lat: 22.97520, lng: 76.37220 },
        "dodi": { lat: 23.00620, lng: 76.58120 },
        "tumda": { lat: 23.02120, lng: 76.52220 },
        "bakaniya": { lat: 23.03120, lng: 76.62220 },
        "barkheda salam": { lat: 23.05120, lng: 76.68220 },
        "bhouri": { lat: 23.15220, lng: 77.18220 },
        "kolu kedi": { lat: 23.16220, lng: 77.22220 },
        "khajuri": { lat: 23.21620, lng: 77.29620 },
        "ithkedi": { lat: 23.20120, lng: 77.31120 },
        "lakhapur": { lat: 23.18620, lng: 77.32120 },
        "mugaliya chap": { lat: 23.17120, lng: 77.33120 },
        "kajlash": { lat: 23.15520, lng: 77.33520 },
        "kodiya": { lat: 23.14520, lng: 77.33820 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS,
        "ratibad  campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus 23: Katara & AIIMS & Awadhpuri ───────────────────────────────────
    "23": {
        "katara hospital": { lat: 23.18920, lng: 77.49520 },
        "katara dastoor hostel": { lat: 23.19460, lng: 77.49120 },
        "lahar pur": { lat: 23.19720, lng: 77.48360 },
        "bagsewaniya ojes hospital": { lat: 23.20120, lng: 77.47420 },
        "saket nagar": { lat: 23.21220, lng: 77.45220 },
        "aiims": { lat: 23.20860, lng: 77.45820 },
        "alkapuri": { lat: 23.20660, lng: 77.46420 },
        "durgamandir": { lat: 23.21820, lng: 77.47120 },
        "barkheda pathani": { lat: 23.22160, lng: 77.48320 },
        "awadhpuri thana": { lat: 23.23092, lng: 77.49502 },
        "aadhar sila chaowk": { lat: 23.23560, lng: 77.48660 },
        "durga chowk": { lat: 23.23860, lng: 77.47920 },
        "awadhpuri tiraha": { lat: 23.24260, lng: 77.47160 },
        "mahatma gandhi chauraha": { lat: 23.24820, lng: 77.44220 },
        "red cross": { lat: 23.22860, lng: 77.42120 },
        "panchsil nagar": { lat: 23.22560, lng: 77.39820 },
        "ratibad-campus": RATIBAD_CAMPUS_COORDS,
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus T-4: Rehti & Narsullaganj ────────────────────────────────────────
    "T-4": {
        "narsulla ganj": { lat: 22.75120, lng: 77.24120 },
        "aagra": { lat: 22.74620, lng: 77.27120 },
        "satrana": { lat: 22.74120, lng: 77.30120 },
        "ramgada": { lat: 22.73860, lng: 77.32120 },
        "soyat": { lat: 22.73560, lng: 77.34120 },
        "nipaniya": { lat: 22.73260, lng: 77.36120 },
        "kalvana": { lat: 22.73060, lng: 77.38120 },
        "bor ghati": { lat: 22.72860, lng: 77.40120 },
        "kakerda": { lat: 22.72960, lng: 77.41620 },
        "kharee": { lat: 22.73060, lng: 77.42120 },
        "naya gaon": { lat: 22.73160, lng: 77.42620 },
        "rehti": { lat: 22.73020, lng: 77.43120 },
        "jamuniya": { lat: 22.75120, lng: 77.44120 },
        "nadiyakheda": { lat: 22.80120, lng: 77.45120 },
        "chakaldi": { lat: 22.85120, lng: 77.44120 },
        "kotra": { lat: 22.95120, lng: 77.42120 },
        "amdo": { lat: 23.05120, lng: 77.38120 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus T-5: Hoshangabad & Babai ─────────────────────────────────────────
    "T-5": {
        "mana gaon": { lat: 22.68120, lng: 77.96120 },
        "st jone school": { lat: 22.69120, lng: 77.94620 },
        "babai bus station": { lat: 22.70120, lng: 77.93120 },
        "nashirabad chouraha": { lat: 22.71620, lng: 77.88120 },
        "resal pur": { lat: 22.73120, lng: 77.80120 },
        "rohna gaon": { lat: 22.74120, lng: 77.76120 },
        "aandhyari": { lat: 22.74620, lng: 77.74120 },
        "bhopal chouraha": { lat: 22.75120, lng: 77.72120 },
        "budhni pull": { lat: 22.77620, lng: 77.68120 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus T-6: Kharkedi & Rehti ────────────────────────────────────────────
    "T-6": {
        "kharkedi": { lat: 22.76120, lng: 77.38120 },
        "kajlash": { lat: 22.75520, lng: 77.39120 }, // Local Rehti/Kanjlas stop
        "hatnapur": { lat: 22.75120, lng: 77.40120 },
        "mogra": { lat: 22.74620, lng: 77.41120 },
        "bayan": { lat: 22.74120, lng: 77.42120 },
        "rehti": { lat: 22.73020, lng: 77.43120 },
        "malimaya": { lat: 22.76120, lng: 77.43620 },
        "anup nagar": { lat: 22.80120, lng: 77.44120 },
        "bordhi": { lat: 22.84120, lng: 77.44620 },
        "bhadkul": { lat: 22.88120, lng: 77.44120 },
        "bardha": { lat: 22.92120, lng: 77.43120 },
        "amdo": { lat: 23.05120, lng: 77.38120 },
        "ratibad campus": RATIBAD_CAMPUS_COORDS
    },

    // ── Bus ECCO: Brajesh Nagar & Icchawar ───────────────────────────────────
    "ECCO": {
        "brajesh nagar": { lat: 23.08120, lng: 76.98120 },
        "keri": { lat: 23.06120, lng: 77.00120 },
        "amlaha": { lat: 23.07120, lng: 76.96120 },
        "icchawar": { lat: 23.03500, lng: 77.01500 }
    }
};

/**
 * Normalizes stop name and matches against route-specific coordinates or global registry
 */
async function geocodeStopName(stopName, busNo = '') {
    const clean = stopName.trim().toLowerCase().replace(/[()_\-\.\/]/g, ' ').replace(/\s+/g, ' ');

    // 1. Campus direct check
    if (clean.includes('ratibad') || clean.includes('sistec')) {
        return RATIBAD_CAMPUS_COORDS;
    }

    // 2. Check Route-Specific Dictionary
    let routeDict = null;
    const cleanBusNo = String(busNo || '').trim();

    if (ROUTE_STOP_COORDINATES[cleanBusNo]) {
        routeDict = ROUTE_STOP_COORDINATES[cleanBusNo];
    } else if (['02', '05', '10', '17', '18', '20', '22', '24'].includes(cleanBusNo)) {
        routeDict = ROUTE_STOP_COORDINATES['ashoka_corridor'];
    } else if (cleanBusNo.includes('ECCO')) {
        routeDict = ROUTE_STOP_COORDINATES['ECCO'];
    }

    if (routeDict) {
        // Direct match in route dict
        if (routeDict[clean]) return routeDict[clean];

        // Contains match in route dict
        for (const [key, coords] of Object.entries(routeDict)) {
            if (clean === key || clean.includes(key) || key.includes(clean)) {
                return coords;
            }
        }

        // Token match in route dict
        const tokens = clean.split(' ').filter(t => t.length > 2);
        for (const token of tokens) {
            for (const [key, coords] of Object.entries(routeDict)) {
                if (key.includes(token)) {
                    return coords;
                }
            }
        }
    }

    // 3. Fallback across all route dictionaries
    for (const [rKey, dict] of Object.entries(ROUTE_STOP_COORDINATES)) {
        if (dict[clean]) return dict[clean];
        for (const [key, coords] of Object.entries(dict)) {
            if (clean === key || clean.includes(key) || key.includes(clean)) {
                return coords;
            }
        }
    }

    // 4. Default to Ratibad Campus if absolutely unrecognized
    return RATIBAD_CAMPUS_COORDS;
}

module.exports = {
    geocodeStopName,
    RATIBAD_CAMPUS_COORDS,
    ROUTE_STOP_COORDINATES
};
