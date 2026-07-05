/**
 * seed_real_routes.js
 * Seeds the SISTecChalo DB with ALL latest real routes parsed from:
 * "Bus Route And schedule collage.pdf" (May 2026 Timings)
 * Sagar Group of Institutions, Ratibad, Bhopal
 *
 * Generated automatically by Python parser.
 * Run: node seed_real_routes.js
 */

const path = require('path');
const fs = require('fs');
let envPath = path.resolve(__dirname, '.env');
if (!fs.existsSync(envPath)) {
    envPath = path.resolve(__dirname, 'SISTecChalo', 'backend', '.env');
}
require('dotenv').config({ path: envPath });
const mongoose = require('mongoose');
const Route    = require('./models/Route');
const Bus      = require('./models/Bus');
const Driver   = require('./models/Driver');
const argon2   = require('argon2');

const rawUri = process.env.MONGODB_URI;
if (!rawUri) {
    console.error('\n❌ ERROR: MONGODB_URI environment variable is not defined!');
    process.exit(1);
}
const MONGODB_URI = rawUri.replace(/\/[^/?]*(\?|$)/, '/sistecChalo$1').replace(/^(mongodb(?:\+srv)?:\/\/[^/]+)$/, '$1/sistecChalo');

// ─── Route definitions from PDF (May 2026 Update) ────────────────────────────
const ROUTES = [
  {
    busNo: '01',
    vehicle: 'MP04 PA 3496',
    name: 'Gandinagar Route',
    color: '#6C63FF',
    driver: 'Ghanshyam Nagar',
    driverMob: '9669660990',
    stops: [
      { name: 'Gandhi Nagar', time: '06:50' },
      { name: 'Asharam Bapu Square', time: '06:55' },
      { name: 'Bhaskar Colony', time: '07:00' },
      { name: 'Data Colony', time: '07:05' },
      { name: 'Panchwati', time: '07:10' },
      { name: 'Bus Stand', time: '07:15' },
      { name: 'Bairahgarh Police Station', time: '07:20' },
      { name: 'Chirayu Hospital', time: '07:25' },
      { name: 'Lalghati', time: '07:35' },
      { name: 'Koh-E-Fiza', time: '07:40' },
      { name: 'Satae Bank Square', time: '07:42' },
      { name: 'Royal Market', time: '07:44' },
      { name: 'Imami gate', time: '07:46' },
      { name: 'Peer Gate', time: '07:48' },
      { name: 'Moti Masjid', time: '07:50' },
      { name: 'Kamla Park', time: '07:52' },
      { name: 'Poly_Technic', time: '07:57' },
      { name: 'Roshanpura', time: '08:00' },
      { name: 'Jawahar Chowk', time: '08:05' },
      { name: 'Bharat Mata Square', time: '08:07' },
      { name: '23 Bataliyan', time: '08:10' },
      { name: '23 Bataliyan', time: '08:30' }
    ],
  },
  {
    busNo: '03',
    vehicle: 'N/A',
    name: 'Karond Route',
    color: '#FF6B6B',
    driver: 'Unknown Driver',
    driverMob: '9669660990',
    stops: [
      { name: 'DwarkaDham SPS Campus', time: '06:45' },
      { name: 'Lambakheda', time: '07:00' },
      { name: 'Karond', time: '07:05' },
      { name: 'Bhanpur', time: '07:10' },
      { name: 'ChholaMandir', time: '07:15' },
      { name: 'Best Prize', time: '07:21' },
      { name: 'Kalyan Nagar', time: '07:22' },
      { name: 'Shiv Mandir', time: '07:23' },
      { name: 'Karond (Sabzi Mandi', time: '07:25' },
      { name: 'DIG Bungla', time: '07:27' },
      { name: 'Nadra Bus Stand', time: '07:32' },
      { name: 'Jahangirabad', time: '07:42' },
      { name: 'PHQ', time: '07:44' },
      { name: 'Roshanpura', time: '07:58' },
      { name: 'Bharat Mata Square', time: '08:02' },
      { name: 'Bharat Mata Square', time: '08:30' }
    ],
  },
  {
    busNo: '04',
    vehicle: 'MP04 PA 3504',
    name: 'Nehru Nagar Road',
    color: '#00F0FF',
    driver: 'Mukesh Shisodiya',
    driverMob: '8251047765',
    stops: [
      { name: 'IBD Kolar Road', time: '07:00' },
      { name: 'DPS School', time: '07:05' },
      { name: 'Bairagarh', time: '07:07' },
      { name: 'Bairagarh', time: '06:10' },
      { name: 'Bairagarh', time: '07:20' },
      { name: 'Babadiya Kala (Salaiya', time: '07:35' },
      { name: 'Rohit Nagar', time: '07:40' },
      { name: 'Aura Moll', time: '07:45' },
      { name: 'Shivay Complex', time: '07:46' },
      { name: '12 No Shop', time: '07:50' },
      { name: 'Sai Board', time: '07:52' },
      { name: '10 No Stop', time: '07:55' },
      { name: 'Arera Petrol Pump', time: '07:57' },
      { name: 'Patrakar Colony', time: '08:00' },
      { name: 'Pancheel Nagar', time: '08:02' },
      { name: 'Vaishali Nagar', time: '08:04' },
      { name: 'Nehru Nagar', time: '08:05' },
      { name: 'Nehru Nagar', time: '08:30' }
    ],
  },
  {
    busNo: '06',
    vehicle: 'N/A',
    name: 'Ashta Route',
    color: '#FFB347',
    driver: 'Unknown Driver',
    driverMob: '9074915343',
    stops: [
      { name: 'Ashta Route', time: '06:20' },
      { name: 'Old Bus Stand', time: '06:21' },
      { name: 'Bhopal_Naka', time: '06:22' },
      { name: 'Bajaranga Colony', time: '06:23' },
      { name: 'Colony Square', time: '06:24' },
      { name: 'Banjari Mata', time: '06:25' },
      { name: 'Kachanariya jod', time: '06:50' },
      { name: 'Kotri', time: '06:53' },
      { name: 'Jat khedi jod', time: '06:55' },
      { name: 'Amlaha', time: '07:05' },
      { name: 'Bhadakhedi jod', time: '07:15' },
      { name: 'Jhagriya By-pass Sehore', time: '07:40' },
      { name: 'Jhagriya', time: '08:05' },
      { name: 'Jhagriya', time: '08:30' }
    ],
  },
  {
    busNo: '07',
    vehicle: 'N/A',
    name: 'Kolar Route',
    color: '#FF2E63',
    driver: 'Unknown Driver',
    driverMob: '7770873503',
    stops: [
      { name: 'Gehnu Kheda', time: '06:55' },
      { name: 'D-Mart', time: '06:58' },
      { name: 'LalitaNagar', time: '06:59' },
      { name: 'NayaPura', time: '07:06' },
      { name: 'Mandakini', time: '07:11' },
      { name: 'LK Hospital', time: '07:18' },
      { name: 'Bansal Hospital', time: '07:27' },
      { name: '10 Number', time: '07:40' },
      { name: 'Arera PetroL pump', time: '07:42' },
      { name: 'KolarTiraha', time: '07:45' },
      { name: 'Punchsil Nagar', time: '07:48' },
      { name: 'Vaishali Nagrar', time: '07:51' },
      { name: 'Neheru Nagar Chauraha', time: '07:55' },
      { name: 'Neheru Nagar Naya Basera', time: '08:05' },
      { name: 'Neheru Nagar Naya Basera', time: '08:30' }
    ],
  },
  {
    busNo: '08',
    vehicle: 'MP04 YR 3428',
    name: 'Fanda Route',
    color: '#A8FF78',
    driver: 'Rahul Verma',
    driverMob: '9669660990',
    stops: [
      { name: 'Amrod', time: '06:40' },
      { name: 'Phanda', time: '06:50' },
      { name: 'Padli jod', time: '06:55' },
      { name: 'Kulas', time: '07:10' },
      { name: 'Choti kulas', time: '07:15' },
      { name: 'Sastakhedi', time: '07:25' },
      { name: 'Dubdi', time: '07:30' },
      { name: 'Borkhedi', time: '07:40' },
      { name: 'Khokhariya', time: '07:45' },
      { name: 'Deriya', time: '08:00' },
      { name: 'Mudla', time: '08:05' },
      { name: 'Narela', time: '08:10' },
      { name: 'Telakhedi', time: '08:15' },
      { name: 'Nandni', time: '08:20' },
      { name: 'Nandni', time: '08:30' }
    ],
  },
  {
    busNo: '09',
    vehicle: 'N/A',
    name: 'Mandideep Route',
    color: '#F7971E',
    driver: 'Satish Tomar',
    driverMob: '9111645969',
    stops: [
      { name: 'Satlapur', time: '06:30' },
      { name: 'Vardhman', time: '06:40' },
      { name: 'Sarakiya', time: '06:50' },
      { name: 'Samardha', time: '07:10' },
      { name: 'Radhapuram', time: '07:11' },
      { name: 'Pal Dhaba', time: '07:13' },
      { name: 'Indus Town', time: '07:15' },
      { name: '11 Meal', time: '07:17' },
      { name: 'Misrod', time: '07:20' },
      { name: 'Ashima Mall', time: '07:25' },
      { name: 'Danish Nagar', time: '07:27' },
      { name: 'Thana', time: '07:30' },
      { name: 'Nagar', time: '07:35' },
      { name: 'Mandir', time: '07:36' },
      { name: 'BJP', time: '07:37' },
      { name: 'College', time: '07:40' },
      { name: 'Durga Petrol Pump', time: '07:42' },
      { name: 'Narmada Bhawan', time: '07:45' },
      { name: 'Panchsil_Nagar', time: '07:47' },
      { name: 'Mata Mandir', time: '07:48' },
      { name: 'PNT', time: '07:50' },
      { name: 'Neheru_Nagar_New Basti', time: '07:51' },
      { name: 'Neheru_Nagar_Square', time: '07:55' },
      { name: 'Neheru_Nagar_Square', time: '08:30' }
    ],
  },
  {
    busNo: '11',
    vehicle: 'N/A',
    name: 'SLV Route',
    color: '#2D5BFF',
    driver: 'Tulsi Das',
    driverMob: '9669660990',
    stops: [
      { name: 'Minal Gate no', time: '07:00' },
      { name: 'Tana Tan Dhaba', time: '07:03' },
      { name: 'Ratnagiri (Azad _Nagar', time: '07:07' },
      { name: 'Anand Nagar', time: '07:10' },
      { name: 'Ishan Park', time: '07:12' },
      { name: 'Orintal Colledge', time: '07:15' },
      { name: 'Bima Hospital', time: '07:36' },
      { name: 'J.KRoad', time: '07:39' },
      { name: 'ITI Chouraha', time: '07:40' },
      { name: 'Shanti Niketan', time: '07:55' },
      { name: 'Bharti Niketan', time: '07:56' },
      { name: '8;02', time: '08:30' }
    ],
  },
  {
    busNo: '13',
    vehicle: 'MP04 PA 2288',
    name: 'Sehore Route',
    color: '#B721FF',
    driver: 'Unknown Driver',
    driverMob: '9669660990',
    stops: [
      { name: 'Kodiya', time: '06:25' },
      { name: 'Ganesh Mandir', time: '06:30' },
      { name: 'Moti Baba Mandir', time: '06:33' },
      { name: 'Bijori Jod', time: '06:45' },
      { name: 'Police Line', time: '06:48' },
      { name: 'Luniya Chouraha', time: '06:50' },
      { name: 'Reliance Petrol Pump', time: '06:52' },
      { name: 'Indore Naka', time: '06:55' },
      { name: 'Kohli Pura', time: '06:57' },
      { name: 'Ganga Ashram', time: '07:02' },
      { name: 'Bhopal_Naka', time: '07:10' },
      { name: 'Chanyak Puri', time: '07:12' },
      { name: 'Chanyak Puri (Vishal Mega Mart', time: '07:15' },
      { name: 'Uljhawan', time: '07:40' },
      { name: 'Khurchani', time: '08:05' },
      { name: 'Khurchani', time: '08:30' }
    ],
  },
  {
    busNo: '14',
    vehicle: 'N/A',
    name: 'Fanda Route',
    color: '#21D4FD',
    driver: 'RajeshPrajapati',
    driverMob: '9617648753',
    stops: [
      { name: 'Kalkeda', time: '07:45' },
      { name: 'Neelbad', time: '08:00' },
      { name: 'Neelbad', time: '08:30' }
    ],
  },
  {
    busNo: '15',
    vehicle: 'MP04 PA 2289',
    name: 'Icchawar Route',
    color: '#43E97B',
    driver: 'Unknown Driver',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhavkhedi', time: '05:15' },
      { name: 'Narshing_kheda', time: '05:40' },
      { name: 'Nagli Jod', time: '05:45' },
      { name: 'Torniya', time: '05:55' },
      { name: 'Ram Nagar', time: '06:05' },
      { name: 'Satpipliya', time: '06:10' },
      { name: 'Vishankhedi', time: '06:20' },
      { name: 'Molakhedi', time: '06:25' },
      { name: 'Khudi', time: '06:55' },
      { name: 'Khakarkheda', time: '07:05' },
      { name: 'Hasnabad', time: '07:10' },
      { name: 'Dait Colony', time: '07:15' },
      { name: 'Indra Nagar', time: '07:20' },
      { name: 'Indra Nagar', time: '08:30' }
    ],
  },
  {
    busNo: '19',
    vehicle: 'MP04 PA 1543',
    name: 'Ashoka Garden Route',
    color: '#FA709A',
    driver: 'Dinesh Jatav',
    driverMob: '9669660990',
    stops: [
      { name: 'Kokta Bypass', time: '07:20' },
      { name: 'SOS_Piplani', time: '07:40' },
      { name: 'Apsara_Takies', time: '07:45' },
      { name: 'Ashoka Garden PanikiTanki', time: '07:51' },
      { name: 'Vallab Bhavan', time: '07:55' },
      { name: 'Dipo', time: '08:10' },
      { name: 'Dipo', time: '08:30' }
    ],
  },
  {
    busNo: '18',
    vehicle: 'MP04 PA 3428',
    name: 'Ashoka Garden Route',
    color: '#FEE140',
    driver: 'Mohmmad',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:50' },
      { name: 'Pushpa Nagar', time: '07:52' },
      { name: 'Sangam Tent House', time: '07:54' },
      { name: '80-feet Road', time: '07:55' },
      { name: 'Ashoka Garden PanikiTanki', time: '08:00' },
      { name: 'Ashoka Garden PanikiTanki', time: '08:30' }
    ],
  },
  {
    busNo: '24',
    vehicle: 'N/A',
    name: 'Katara Route',
    color: '#8A2BE2',
    driver: 'Unknown Driver',
    driverMob: '9669660990',
    stops: [
      { name: 'Katara Hospital', time: '06:55' },
      { name: 'Katara Dastoor Hostel', time: '07:02' },
      { name: 'Lahar Pur', time: '07:06' },
      { name: 'Bagsewaniya Qjes Hospital', time: '07:10' },
      { name: 'Saket Nagar', time: '07:15' },
      { name: 'AIIMS', time: '07:17' },
      { name: 'Alkapuri', time: '07:20' },
      { name: 'DurgaMandir', time: '07:21' },
      { name: 'Barkheda Pathani', time: '07:25' },
      { name: 'Awadhpuri Thana', time: '07:30' },
      { name: 'Aadhar Sila Chaowk', time: '13:32' },
      { name: 'Mahatma Gandhi Chauraha', time: '07:38' },
      { name: 'Red Cross', time: '07:55' },
      { name: 'Panchsil Nagar', time: '07:57' },
      { name: 'Panchsil Nagar', time: '08:30' }
    ],
  },
  {
    busNo: '26',
    vehicle: 'MP04 YR 4318',
    name: 'Ashta Route',
    color: '#32CD32',
    driver: 'Unknown Driver',
    driverMob: '8989878725',
    stops: [
      { name: 'Alipur', time: '06:20' },
      { name: 'Old Bus Stand', time: '06:21' },
      { name: 'Bhopal Naka', time: '06:22' },
      { name: 'Bajaranga Colony', time: '06:23' },
      { name: 'Colony Square', time: '06:24' },
      { name: 'Banjari Mata', time: '06:25' },
      { name: 'Kachanariya jod', time: '06:50' },
      { name: 'Kotri', time: '06:53' },
      { name: 'Jat khedi jod', time: '06:55' },
      { name: 'Amlaha', time: '07:05' },
      { name: 'Bhadakhedi jod', time: '07:15' },
      { name: 'Goodwela', time: '07:30' },
      { name: 'Jhagriya By-pass Sehore', time: '07:40' },
      { name: 'Jhagriya', time: '08:05' },
      { name: 'Jhagriya', time: '08:30' }
    ],
  },
  {
    busNo: '27',
    vehicle: 'MP04 YR 3427',
    name: 'Rehti Route',
    color: '#FF4500',
    driver: 'Unknown Driver',
    driverMob: '9669660990',
    stops: [
      { name: 'Narsullaganj', time: '05:30' },
      { name: 'Rala', time: '05:35' },
      { name: 'Satrana', time: '05:50' },
      { name: 'Nipaniya', time: '06:00' },
      { name: 'Ramgada', time: '06:05' },
      { name: 'Kakvana', time: '06:10' },
      { name: 'Bor ghati', time: '06:20' },
      { name: 'Rehti', time: '06:30' },
      { name: 'Malimaya', time: '06:40' },
      { name: 'Bordi', time: '06:55' },
      { name: 'Amdo', time: '07:10' },
      { name: 'Bilkisganj', time: '08:25' },
      { name: 'Bilkisganj', time: '08:30' }
    ],
  },
  {
    busNo: '28',
    vehicle: 'MP04 YR 4386',
    name: 'Diwadiya IcchawarRoute',
    color: '#FF8C00',
    driver: 'Krishna Verma',
    driverMob: '9977606876',
    stops: [
      { name: 'Diwadiya', time: '06:10' },
      { name: 'Jhalki', time: '06:20' },
      { name: 'Kushal Pura', time: '06:30' },
      { name: 'Amla', time: '06:40' },
      { name: 'Nayapura', time: '06:45' },
      { name: 'Siradi', time: '06:55' },
      { name: 'Mandi', time: '06:58' },
      { name: 'Bus Stand', time: '07:00' },
      { name: 'Thana', time: '07:02' },
      { name: 'Uljhawan', time: '08:10' },
      { name: 'Uljhawan', time: '08:30' }
    ],
  },
  {
    busNo: 'T-4',
    vehicle: 'MP04 PA 4443',
    name: 'Rehti Route',
    color: '#008080',
    driver: 'Unknown Driver',
    driverMob: '9669660990',
    stops: [
      { name: 'Agra', time: '05:15' },
      { name: 'Majarkui', time: '06:00' },
      { name: 'Naya Gaon', time: '06:05' },
      { name: 'Karri', time: '06:10' },
      { name: 'Khakarda', time: '06:11' },
      { name: 'Soyat', time: '06:30' },
      { name: 'Jamuniya', time: '06:35' },
      { name: 'Nadhiyakheda', time: '06:37' },
      { name: 'Kotra', time: '06:40' },
      { name: 'Chakaldi', time: '06:55' },
      { name: 'Dhaba Gaon', time: '07:00' },
      { name: 'Amdo', time: '07:10' },
      { name: 'Amdo', time: '08:30' }
    ],
  },
  {
    busNo: 'T-5',
    vehicle: 'MP04 PA 4442',
    name: 'Hoshangabad Route',
    color: '#9400D3',
    driver: 'Rahul Vishvkarma',
    driverMob: '9669660990',
    stops: [
      { name: 'Mana Gaon', time: '05:15' },
      { name: 'St Jone School', time: '05:25' },
      { name: 'Babai Bus Station', time: '05:30' },
      { name: 'Nashirabad Chouraha', time: '05:35' },
      { name: 'CMRise School', time: '05:40' },
      { name: 'Resal Pur', time: '06:10' },
      { name: 'Rohna Gaon', time: '06:25' },
      { name: 'Aandhyari', time: '06:30' },
      { name: 'Shainath STD', time: '06:45' },
      { name: 'Budhni Pull', time: '06:55' },
      { name: 'Budhni Pull', time: '08:30' }
    ],
  },
  {
    busNo: 'T-6',
    vehicle: 'N/A',
    name: 'Bakaniya Route',
    color: '#00FF7F',
    driver: 'Jitendra Prajapati',
    driverMob: '8965815880',
    stops: [
      { name: 'Ratikheda', time: '06:20' },
      { name: 'Dodi', time: '06:25' },
      { name: 'Sonkach', time: '06:55' },
      { name: 'Kharkheda', time: '07:00' },
      { name: 'Toomda', time: '07:15' },
      { name: 'Bakaniya', time: '07:30' },
      { name: 'Barkheda', time: '07:40' },
      { name: 'Kolukhedi', time: '07:55' },
      { name: 'Khajuri', time: '08:00' },
      { name: 'Lakhapur', time: '08:10' },
      { name: 'Kajlash', time: '08:15' },
      { name: 'Kodiya', time: '08:20' },
      { name: 'Kodiya', time: '08:30' }
    ],
  },
  {
    busNo: '05',
    vehicle: 'MP04 PA 3510',
    name: 'Ashoka Garden Route',
    color: '#FF1493',
    driver: 'Babloo Meena',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:20' },
      { name: 'Pushpa Nagar', time: '07:22' },
      { name: 'Sangam Tent House', time: '07:23' },
      { name: '80-feet Road', time: '07:25' },
      { name: 'Ashoka Garden PanikiTanki', time: '07:30' },
      { name: 'Prabhat Square', time: '08:30' }
    ],
  },
  {
    busNo: '16',
    vehicle: 'MP04 PA 2515',
    name: 'Ashoka Garden Route',
    color: '#1E90FF',
    driver: 'Rajesh Shisodiya',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:20' },
      { name: 'Pushpa Nagar', time: '07:22' },
      { name: 'Sangam Tent House', time: '07:23' },
      { name: '80-feet Road', time: '07:25' },
      { name: 'Ashoka Garden PanikiTanki', time: '07:30' },
      { name: 'Prabhat Square', time: '08:30' }
    ],
  },
  {
    busNo: '18',
    vehicle: 'MP04 PA 3428',
    name: 'Ashoka Garden Route',
    color: '#FFD700',
    driver: 'Mohmad',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:20' },
      { name: 'Pushpa Nagar', time: '07:22' },
      { name: 'Sangam Tent House', time: '07:23' },
      { name: '80-feet Road', time: '07:25' },
      { name: 'Ashoka Garden PanikiTanki', time: '07:30' },
      { name: 'Prabhat Square', time: '08:30' }
    ],
  },
  {
    busNo: '04',
    vehicle: 'MP04 PA 3504',
    name: 'Ashoka Garden Route',
    color: '#FF00FF',
    driver: 'Mukesh Shiodiya',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:20' },
      { name: 'Pushpa Nagar', time: '07:22' },
      { name: 'Sangam Tent House', time: '07:23' },
      { name: '80-feet Road', time: '07:25' },
      { name: 'Ashoka Garden PanikiTanki', time: '07:30' },
      { name: 'Prabhat Square', time: '08:30' }
    ],
  },
  {
    busNo: 'Private Vehicle',
    vehicle: 'MP04 1141',
    name: 'Ashoka Gardan Route',
    color: '#00FF00',
    driver: 'Gopal',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:20' },
      { name: 'Pushpa Nagar', time: '07:22' },
      { name: 'Sangam Tent House', time: '07:23' },
      { name: '80-feet Road', time: '07:25' },
      { name: 'Ashoka Garden PanikiTanki', time: '07:30' },
      { name: 'Prabhat Square', time: '07:32' },
      { name: 'Prabhat Square', time: '08:30' }
    ],
  },
  {
    busNo: 'Private Vehicle',
    vehicle: 'MP04 PA 7220',
    name: 'Ashoka Gardan Route',
    color: '#4B0082',
    driver: 'Sahrukh',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:20' },
      { name: 'Pushpa Nagar', time: '07:22' },
      { name: 'Sangam Tent House', time: '07:23' },
      { name: '80-feet Road', time: '07:25' },
      { name: 'Prabhat Square', time: '07:32' },
      { name: 'Prabhat Square', time: '08:30' }
    ],
  },
  {
    busNo: 'Private Vehicle',
    vehicle: 'MP04 PA 2127',
    name: 'Ashoka Garden Route',
    color: '#0000FF',
    driver: 'Farheed Bhai',
    driverMob: '9669660990',
    stops: [
      { name: 'Bhopal Railway station Plat form-1', time: '07:20' },
      { name: 'Pushpa Nagar', time: '07:22' },
      { name: 'Sangam Tent House', time: '07:23' },
      { name: '80-feet Road', time: '07:25' },
      { name: 'Ashoka Garden PanikiTanki', time: '07:30' },
      { name: 'Jinsi Squre', time: '07:40' },
      { name: 'Dipo', time: '07:50' },
      { name: 'Dipo', time: '08:30' }
    ],
  },
  {
    busNo: '12',
    vehicle: 'MP04 PA 3521',
    name: 'Neelbad Route',
    color: '#7FFF00',
    driver: 'Arjun Maran',
    driverMob: '9669660990',
    stops: [
      { name: 'Neelbad', time: '08:10' },
      { name: 'Neelbad', time: '08:15' },
      { name: 'Neelbad', time: '08:30' }
    ],
  },
  {
    busNo: '21',
    vehicle: 'MP04 PA 9712',
    name: 'Neelbad Route',
    color: '#D2691E',
    driver: 'Ahad Ali',
    driverMob: '9669660990',
    stops: [
      { name: 'Neelbad', time: '08:10' },
      { name: 'Neelbad', time: '08:15' },
      { name: 'Neelbad', time: '08:30' }
    ],
  },
  {
    busNo: '23',
    vehicle: 'MP04 PA 1503',
    name: 'Neelbad Route',
    color: '#FF7F50',
    driver: 'Sandeep Vishvkarma',
    driverMob: '9669660990',
    stops: [
      { name: 'Neelbad', time: '08:10' },
      { name: 'Neelbad', time: '08:15' },
      { name: 'Neelbad', time: '08:30' }
    ],
  }
];

// All routes terminate at Ratibad Campus
const RATIBAD = { lat: 23.1270, lng: 77.3494 };

async function seed(shouldDisconnect = true) {
  if (mongoose.connection.readyState !== 1) {
    console.log('🔌 Connecting to MongoDB (SISTecChalo)...');
    await mongoose.connect(MONGODB_URI, { dbName: 'sistecChalo' });
    console.log(`✅ Connected to: ${mongoose.connection.name}`);
  } else {
    console.log('🔌 MongoDB is already connected, reusing connection...');
  }

  // Clear existing routes, buses, and drivers
  await Route.deleteMany({});
  await Bus.deleteMany({});
  await Driver.deleteMany({});
  console.log('🧹 Cleared existing routes, buses, and drivers');

  const defaultPassword = process.env.DEFAULT_SEED_PASSWORD || '123456';
  const hashedPassword = await argon2.hash(defaultPassword);
  console.log(`🔑 Generated Argon2 hash for driver default password: "${defaultPassword}"`);

  // Sort the raw ROUTES array by bus number before seeding
  ROUTES.sort((a, b) => {
    const aIsNum = /^\d+$/.test(a.busNo);
    const bIsNum = /^\d+$/.test(b.busNo);
    if (aIsNum && bIsNum) {
      return parseInt(a.busNo) - parseInt(b.busNo);
    }
    if (aIsNum) return -1;
    if (bIsNum) return 1;

    const aIsT = /^T-\d+$/i.test(a.busNo);
    const bIsT = /^T-\d+$/i.test(b.busNo);
    if (aIsT && bIsT) {
      const aVal = parseInt(a.busNo.replace(/\D/g, ''));
      const bVal = parseInt(b.busNo.replace(/\D/g, ''));
      return aVal - bVal;
    }
    if (aIsT) return -1;
    if (bIsT) return 1;

    return a.busNo.localeCompare(b.busNo);
  });

  // Now, create Routes, Drivers, and Buses in a single iteration!
  for (let ri = 0; ri < ROUTES.length; ri++) {
    const r = ROUTES[ri];
    
    // Normalize typos and duplicates from PDF pages to get the clean base route name
    let baseRouteName = r.name.trim();
    if (baseRouteName === 'Ashoka Gardan Route' || baseRouteName === 'Ashoka Garden') {
      baseRouteName = 'Ashoka Garden Route';
    } else if (baseRouteName === 'Diwadiya IcchawarRoute' || baseRouteName === 'Diwadiya + Ichhawar Route') {
      baseRouteName = 'Diwadiya + Ichhawar Route';
    } else if (baseRouteName === 'Nehru Nagar Road') {
      baseRouteName = 'Kolar + Nehru Nagar Road';
    } else if (r.busNo === '14' && r.driver === 'RajeshPrajapati') {
      baseRouteName = 'Neelbad Route';
    }
    
    let displayBusNo = r.busNo;
    if (displayBusNo === 'Private Vehicle') {
      const parts = (r.vehicle || '').split(' ');
      displayBusNo = parts.length > 0 ? `Pvt ${parts[parts.length - 1]}` : 'Pvt';
    }
    const finalRouteName = `${baseRouteName} (Bus no: ${displayBusNo})`;

    // Create a dedicated Route document for this single bus schedule
    const stopsWithNames = r.stops.map(stop => ({ name: stop.name }));
    const route = await Route.create({
      name: finalRouteName,
      color: r.color,
      stops: stopsWithNames,
      coordinates: [], // Empty — no fake polyline
    });

    // Create driver
    // Generate clean driver username: driver01, driverT-4, driverECCO
    const baseUsername = `driver${r.busNo}`.replace(/\s+/g, '').replace(/[^a-zA-Z0-9]/g, '').toLowerCase();
    
    let username = baseUsername;
    let suffix = 2;
    while (await Driver.findOne({ username: username })) {
      username = `${baseUsername}${suffix}`;
      suffix++;
    }
    
    const driver = await Driver.create({
      username: username,
      password: hashedPassword,
      name: r.driver || `Driver Bus ${r.busNo}`,
      contactNumber: r.driverMob || '9876543210',
      status: 'Active',
    });

    // Create bus and link to driver and dedicated route
    const bus = await Bus.create({
      busNumber: r.vehicle || 'N/A',           // vehicle number as busNumber
      name: `Bus ${r.busNo} - ${route.name}`,
      routeId: route._id.toString(),
      routeName: route.name,
      routeColor: route.color,
      currentLat: RATIBAD.lat,
      currentLng: RATIBAD.lng,
      heading: 0,
      speed: 0,
      status: 'Offline',
      driverId: driver._id.toString(),
      occupancy: 'Low',
      etas: [],
      lastUpdated: new Date(),
    });

    // Update driver with assigned bus
    driver.assignedBus = bus._id.toString();
    await driver.save();

    console.log(`✅ Bus, Driver & Dedicated Route ${r.busNo} (${username}): ${route.name} (${r.stops.length} stops)`);
  }

  console.log(`\n🎉 Seeded ${ROUTES.length} unique routes, buses and drivers successfully!`);
  if (shouldDisconnect) {
    await mongoose.disconnect();
    console.log('🔌 Disconnected from MongoDB');
  }
}

if (require.main === module) {
  seed(true).catch(err => {
    console.error('❌ Seed failed:', err);
    mongoose.disconnect();
    process.exit(1);
  });
}

module.exports = {
  seed,
  ROUTES
};


