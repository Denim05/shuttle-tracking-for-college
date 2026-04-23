
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { COLORS } from '../constants/theme';

import { useAppStore } from '@/hooks/useAppStore';
import LocationTracker from '../components/LocationTracker';

// Prevent the splash screen from auto-hiding before asset loading is complete.
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [loaded] = useFonts({
    // SpaceMono: require('../assets/fonts/SpaceMono-Regular.ttf'),
  });

  const { fetchInitialData } = useAppStore();

  useEffect(() => {
    // if (loaded) {
    SplashScreen.hideAsync();
    fetchInitialData();
    // }
  }, [loaded, fetchInitialData]);

  // if (!loaded) {
  //   return null;
  // }

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <LocationTracker />
      <StatusBar style="light" backgroundColor="transparent" translucent={true} />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: COLORS.background },
          animation: 'fade', // Smooth ease between screens
        }}
      >
        <Stack.Screen name="index" />
        <Stack.Screen name="user/index" options={{ animation: 'slide_from_right' }} />
        <Stack.Screen name="admin/dashboard" options={{ animation: 'slide_from_right' }} />
      </Stack>
    </GestureHandlerRootView>
  );
}
