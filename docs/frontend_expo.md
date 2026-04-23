# React Native (Expo) Frontend Documentation

The Manager/Admin frontend is built using Expo, Expo Router, React Native, and Zustand for state management. It utilizes Tailwind CSS (NativeWind or equivalent class-based styling) for UI design.

## Project Structure

```text
app/
├── _layout.tsx       # Root layout and context providers
├── index.tsx         # Login screen / entry point
├── admin/            # Admin dashboard screens
├── manager/          # Manager dashboard screens
├── user/             # Standard user screens
├── (tabs)/           # Tab-based navigation (unused/legacy)
└── modal.tsx         # Reusable modal overlays

components/
├── ui/               # Reusable UI components (Buttons, Inputs)
├── maps/             # Map overlays and markers
├── forms/            # Form components

constants/
├── Colors.ts         # Theme definitions
└── mockData.ts       # Mock payloads for development

hooks/
├── useAuth.ts        # Authentication state via Zustand
├── useSocket.ts      # Socket.io connection lifecycle
└── useLocation.ts    # React Native Location wrappers
```

## State Management (Zustand)

Instead of passing props deeply, the app relies on Zustand stores:

- **`useAuthStore`**: Manages the currently logged-in user, JWT token, and role. Helps with top-level routing decisions in `_layout.tsx`.
- **`useBusStore`**: Stores the real-time position of buses. Updated via Socket.io listeners.

## Navigation and Routing

Routing is handled by **Expo Router**:

1. `app/index.tsx` serves as the initial `LoginScreen`.
2. Based on the role selected ("Manager", "Admin", "Student"), `expo-router`'s `useRouter().replace()` directs the user to:
   - `/manager` (Manager Dashboard)
   - `/admin` (Admin Dashboard)
   - `/user` (User/Student Dashboard)

## Map Integration

The app uses `react-native-maps`:

- Displays buses as custom markers based on real-time longitude and latitude updates.
- Renders default routes via `Polyline`.
- Custom components like `BusMarker` are used to rotate icons based on the `heading` property received from the socket payload.

## Styling

- Styling is predominantly done using utility classes (e.g., `className="flex-1 bg-white p-4"`) mapped securely using `nativewind` or `tailwind-merge`.
- Shared constants like `Colors` provide strictly themed elements like `$primary` blue or `zinc-800` backgrounds.
