import BusMap from '@/components/BusMap';
import RouteSelectionSheet from '@/components/RouteSelectionSheet';
import { COLORS, SHADOWS, SPACING } from '@/constants/theme';
import { useAppStore } from '@/hooks/useAppStore';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import React, { useEffect, useState } from 'react';
import { Alert, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

export default function UserHomeScreen() {
  const router = useRouter();
  const { 
    fetchInitialData, 
    buses, 
    stops, 
    routes, 
    selectedRouteId,
    setSelectedRoute,
    setSelectedStop
  } = useAppStore();

  const [filterVisible, setFilterVisible] = useState(false);

  useEffect(() => {
    fetchInitialData();
  }, []);

  const handleStopPress = (stopId: string) => {
      setSelectedStop(stopId);
      Alert.alert('Stop Selected', `Stop ID: ${stopId}`);
  };

  const handleBusPress = (busId: string) => {
      // Could show bus details modal here
      console.log('Bus Pressed:', busId);
  };

  const activeFilterCount = (selectedRouteId ? 1 : 0);

  return (
    <View style={styles.container}>
      {/* Full Screen Map */}
      <BusMap 
        buses={buses}
        stops={stops}
        routes={routes}
        selectedRouteId={selectedRouteId}
        onStopPress={handleStopPress}
        onBusPress={handleBusPress}
      />

      {/* Header Overlay */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Campus Shuttle</Text>
        <Text style={styles.headerSubtitle}>Live Tracking</Text>
      </View>

      {/* Floating Filter Button */}
      <TouchableOpacity 
        style={styles.fab} 
        onPress={() => setFilterVisible(true)}
        activeOpacity={0.8}
      >
        <View style={styles.fabIcon}>
             <Ionicons name="options" size={24} color="#000" />
        </View>
        <Text style={styles.fabText}>
            {selectedRouteId ? 'FILTER ON' : 'FILTER MAP'}
        </Text>
        {activeFilterCount > 0 && (
            <View style={styles.badge}>
                <Text style={styles.badgeText}>{activeFilterCount}</Text>
            </View>
        )}
      </TouchableOpacity>

      {/* Selection Modal */}
      <RouteSelectionSheet 
        visible={filterVisible} 
        onClose={() => setFilterVisible(false)} 
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  header: {
      position: 'absolute',
      top: 60,
      left: SPACING.l,
      zIndex: 10,
  },
  headerTitle: {
      fontSize: 28,
      fontWeight: '900',
      color: COLORS.text,
      textShadowColor: 'rgba(0,0,0,0.5)',
      textShadowOffset: { width: 0, height: 2 },
      textShadowRadius: 4,
  },
  headerSubtitle: {
      fontSize: 14,
      color: COLORS.primary,
      fontWeight: 'bold',
      letterSpacing: 2,
      textShadowColor: 'rgba(0,0,0,0.8)',
      textShadowOffset: { width: 0, height: 1 },
      textShadowRadius: 2,
  },
  fab: {
      position: 'absolute',
      bottom: 100, // Above tab bar
      alignSelf: 'center',
      backgroundColor: COLORS.primary,
      borderRadius: 30,
      paddingVertical: 12,
      paddingHorizontal: 24,
      flexDirection: 'row',
      alignItems: 'center',
      ...SHADOWS.glow,
      zIndex: 10,
  },
  fabIcon: {
      marginRight: 8,
  },
  fabText: {
      color: '#000',
      fontWeight: 'bold',
      fontSize: 14,
      letterSpacing: 1,
  },
  badge: {
     position: 'absolute',
     top: -5,
     right: -5,
     backgroundColor: 'red',
     borderRadius: 10,
     width: 20,
     height: 20,
     justifyContent: 'center',
     alignItems: 'center',
     borderWidth: 2,
     borderColor: COLORS.background, 
  },
  badgeText: {
      color: 'white',
      fontSize: 10,
      fontWeight: 'bold',
  }
});
