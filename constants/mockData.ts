export interface Bus {
  id: string;
  routeId: string; // Added to link bus to route
  routeName: string;
  routeColor: string;
  currentLat: number;
  currentLng: number;
  occupancyLevel: "Low" | "Medium" | "High";
  status: "On-time" | "Delayed";
  heading: number; // 0-360 degrees for icon rotation
  nextStopId: string;
  speed?: number; // Speed in m/s
}

export interface Stop {
  id: string;
  name: string;
  lat: number;
  lng: number;
  routes: string[]; // List of route names stopping here
  nextArrivals: {
    routeId: string;
    routeName: string;
    arrivalTime: string; // ISO string or simple time
    etaMinutes: number;
  }[];
}

export interface Route {
  id: string;
  name: string;
  color: string;
  coordinates: { latitude: number; longitude: number }[];
}

// Campus Center: ~ 37.78825, -122.4324 (Simulated SF generic location or we can use a specific campus)
// Let's use a generic campus-like area.
// Campus Center: SISTEC Gandhi Nagar (Approx Center of Logic)
export const CAMPUS_CENTER = { lat: 23.2863, lng: 77.3421 };

export const MOCK_ROUTES: Route[] = [
  {
    id: "R1",
    name: "Blue Route",
    color: "#007AFF",
    coordinates: [
      { latitude: 37.7749, longitude: -122.4194 },
      { latitude: 37.7755, longitude: -122.418 },
      { latitude: 37.776, longitude: -122.4165 },
      { latitude: 37.7765, longitude: -122.415 },
    ],
  },
  {
    id: "R2",
    name: "Gold Route",
    color: "#FFD700",
    coordinates: [
      { latitude: 37.7749, longitude: -122.4194 },
      { latitude: 37.774, longitude: -122.42 },
      { latitude: 37.773, longitude: -122.421 },
      { latitude: 37.7725, longitude: -122.4225 },
    ],
  },
  {
    id: "R3",
    name: "Gandinagar Route",
    color: "#9C27B0",
    coordinates: [
      { latitude: 23.2863, longitude: 77.3421 }, // Gandhi Nagar
      { latitude: 23.275, longitude: 77.355 }, // Halalpur
      { latitude: 23.2706, longitude: 77.3718 }, // Lalghati
      { latitude: 23.265, longitude: 77.375 }, // Koh-E-Fiza
      { latitude: 23.25, longitude: 77.395 }, // Kamla Park
      { latitude: 23.2435, longitude: 77.4044 }, // Poly Technic
      { latitude: 23.2355, longitude: 77.397 }, // Jawahar Chowk
      { latitude: 23.225, longitude: 77.39 }, // Bharat Mata
      { latitude: 23.21, longitude: 77.38 }, // Bataliyan
      { latitude: 23.161, longitude: 77.3512 }, // Ratibad
    ],
  },
];

export const MOCK_STOPS: Stop[] = [
  {
    id: "S1",
    name: "Main Gate",
    lat: 37.7749,
    lng: -122.4194,
    routes: ["Blue Route", "Gold Route"],
    nextArrivals: [
      {
        routeId: "R1",
        routeName: "Blue Route",
        arrivalTime: "10:05 AM",
        etaMinutes: 3,
      },
      {
        routeId: "R2",
        routeName: "Gold Route",
        arrivalTime: "10:08 AM",
        etaMinutes: 6,
      },
    ],
  },
  {
    id: "S2",
    name: "Library",
    lat: 37.7765,
    lng: -122.415,
    routes: ["Blue Route"],
    nextArrivals: [
      {
        routeId: "R1",
        routeName: "Blue Route",
        arrivalTime: "10:12 AM",
        etaMinutes: 10,
      },
    ],
  },
  {
    id: "S3",
    name: "Dorms",
    lat: 37.7725,
    lng: -122.4225,
    routes: ["Gold Route"],
    nextArrivals: [
      {
        routeId: "R2",
        routeName: "Gold Route",
        arrivalTime: "10:02 AM",
        etaMinutes: 1,
      },
    ],
  },
  // Gandinagar Route Stops (Bhopal coordinates approximated)
  {
    id: "GS1",
    name: "Gandhi Nagar",
    lat: 23.2863,
    lng: 77.3421,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "6:35 AM",
        etaMinutes: 0,
      },
    ],
  },
  {
    id: "GS2",
    name: "Asharam Bapu Square",
    lat: 23.284,
    lng: 77.345,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "6:40 AM",
        etaMinutes: 5,
      },
    ],
  },
  {
    id: "GS3",
    name: "Bhaskar Colony",
    lat: 23.282,
    lng: 77.348,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "6:45 AM",
        etaMinutes: 10,
      },
    ],
  },
  {
    id: "GS4",
    name: "Data Colony",
    lat: 23.28,
    lng: 77.35,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "6:50 AM",
        etaMinutes: 15,
      },
    ],
  },
  {
    id: "GS5",
    name: "Panchwati",
    lat: 23.278,
    lng: 77.352,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "6:55 AM",
        etaMinutes: 20,
      },
    ],
  },
  {
    id: "GS6",
    name: "Halalpur (Bus Stand)",
    lat: 23.275,
    lng: 77.355,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:00 AM",
        etaMinutes: 25,
      },
    ],
  },
  {
    id: "GS7",
    name: "Bairahgarh Police Station",
    lat: 23.2721,
    lng: 77.3585,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:05 AM",
        etaMinutes: 30,
      },
    ],
  },
  {
    id: "GS8",
    name: "Chirayu Hospital",
    lat: 23.27,
    lng: 77.365,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:10 AM",
        etaMinutes: 35,
      },
    ],
  },
  {
    id: "GS9",
    name: "Lalghati",
    lat: 23.2706,
    lng: 77.3718,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:20 AM",
        etaMinutes: 45,
      },
    ],
  },
  {
    id: "GS10",
    name: "Koh-E-Fiza",
    lat: 23.265,
    lng: 77.375,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:25 AM",
        etaMinutes: 50,
      },
    ],
  },
  {
    id: "GS11",
    name: "Satae Bank Square",
    lat: 23.262,
    lng: 77.378,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:27 AM",
        etaMinutes: 52,
      },
    ],
  },
  {
    id: "GS12",
    name: "Royal Market",
    lat: 23.2598,
    lng: 77.3805,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:29 AM",
        etaMinutes: 54,
      },
    ],
  },
  {
    id: "GS13",
    name: "Imami gate",
    lat: 23.257,
    lng: 77.382,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:31 AM",
        etaMinutes: 56,
      },
    ],
  },
  {
    id: "GS14",
    name: "Peer Gate",
    lat: 23.255,
    lng: 77.384,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:33 AM",
        etaMinutes: 58,
      },
    ],
  },
  {
    id: "GS15",
    name: "Moti Masjid",
    lat: 23.2536,
    lng: 77.3887,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:35 AM",
        etaMinutes: 60,
      },
    ],
  },
  {
    id: "GS16",
    name: "Kamla Park",
    lat: 23.25,
    lng: 77.395,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:37 AM",
        etaMinutes: 62,
      },
    ],
  },
  {
    id: "GS17",
    name: "Poly Technic",
    lat: 23.2435,
    lng: 77.4044,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:42 AM",
        etaMinutes: 67,
      },
    ],
  },
  {
    id: "GS18",
    name: "Roshanpura",
    lat: 23.238,
    lng: 77.4,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:45 AM",
        etaMinutes: 70,
      },
    ],
  },
  {
    id: "GS19",
    name: "Jawahar Chowk",
    lat: 23.2355,
    lng: 77.397,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:50 AM",
        etaMinutes: 75,
      },
    ],
  },
  {
    id: "GS20",
    name: "Bharat Mata Square",
    lat: 23.225,
    lng: 77.39,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:52 AM",
        etaMinutes: 77,
      },
    ],
  },
  {
    id: "GS21",
    name: "23 Bataliyan",
    lat: 23.21,
    lng: 77.38,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "7:55 AM",
        etaMinutes: 80,
      },
    ],
  },
  {
    id: "GS22",
    name: "Ratibad Campus",
    lat: 23.161,
    lng: 77.3512,
    routes: ["Gandinagar Route"],
    nextArrivals: [
      {
        routeId: "R3",
        routeName: "Gandinagar Route",
        arrivalTime: "8:15 AM",
        etaMinutes: 100,
      },
    ],
  },
];

export const MOCK_BUSES: Bus[] = [
  {
    id: "B1",
    routeId: "R1",
    routeName: "Blue Route",
    routeColor: "#007AFF",
    currentLat: 37.7752,
    currentLng: -122.4185,
    occupancyLevel: "Low",
    status: "On-time",
    heading: 65,
    nextStopId: "S2",
  },
  {
    id: "B2",
    routeId: "R2",
    routeName: "Gold Route",
    routeColor: "#FFD700",
    currentLat: 37.7735,
    currentLng: -122.4205,
    occupancyLevel: "High",
    status: "Delayed",
    heading: 200,
    nextStopId: "S3",
  },
  {
    id: "B3",
    routeId: "R3",
    routeName: "Gandinagar Route",
    routeColor: "#9C27B0",
    currentLat: 23.275, // Stopped at Halalpur roughly
    currentLng: 77.355,
    occupancyLevel: "Medium",
    status: "On-time",
    heading: 160,
    nextStopId: "GS7", // Next stop Bairahgarh
  },
];
