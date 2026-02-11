
import * as Location from 'expo-location';
import { useEffect, useState } from 'react';
import { useAppStore } from '../hooks/useAppStore';

export default function LocationTracker() {
  const isDriverMode = useAppStore((state) => state.isDriverMode);
  const updateDriverLocation = useAppStore((state) => state.updateDriverLocation);
  const [subscription, setSubscription] = useState<Location.LocationSubscription | null>(null);

  useEffect(() => {
    let sub: Location.LocationSubscription | null = null;

    const startTracking = async () => {
      // If we are already tracking, do nothing? Or maybe recreate?
      // For now, let's assume if subscription exists we are good, BUT
      // if isDriverMode becomes false, we need to stop.
      
      if (isDriverMode) {
        console.log('Requesting permissions...');
        const { status } = await Location.requestForegroundPermissionsAsync(); // Changed to request
        
        if (status !== 'granted') {
             console.warn('Location permission not granted in Tracker');
             // Alerting the user is better
             // Alert.alert('Permission needed', 'Please grant location permission to drive.');
             return;
        }

        console.log('Starting watchPositionAsync...');
        sub = await Location.watchPositionAsync(
          {
            accuracy: Location.Accuracy.BestForNavigation,
            timeInterval: 500, // Update every 500ms
            distanceInterval: 0, // Update even if stationary (capture GPS jitter)
          },
          (location) => {
            console.log('📍 Location Update:', location.coords.latitude, location.coords.longitude);
            updateDriverLocation(
                location.coords.latitude, 
                location.coords.longitude,
                location.coords.heading || 0,
                location.coords.speed || 0
            );
          }
        );
        setSubscription(sub);
      } else {
        // Stop tracking
        if (subscription) {
            subscription.remove();
            setSubscription(null);
        }
      }
    };

    startTracking();

    return () => {
      if (sub) {
        sub.remove();
      }
    };
  // We want to re-run this effect when isDriverMode changes.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isDriverMode, updateDriverLocation]);

  return null; // This component renders nothing
}
