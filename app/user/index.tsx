import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import BottomSheet from '../../components/BottomSheet';
import BusMap from '../../components/BusMap';
import ProfileModal from '../../components/ProfileModal';
import RouteSelectionSheet from '../../components/RouteSelectionSheet';
import { COLORS, SHADOWS, SPACING } from '../../constants/theme';
import { useAppStore } from '../../hooks/useAppStore';

export default function UserHomeScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const [profileVisible, setProfileVisible] = useState(false);
  const [filterVisible, setFilterVisible] = useState(true); // Open by default on login
  
  const { 
    buses, stops, routes, selectedRouteId, 
    setSelectedStop,
    fetchInitialData, isLowDataMode, setLowDataMode, socketConnected
  } = useAppStore();

  useEffect(() => {
    fetchInitialData();
  }, [fetchInitialData]);

  const handleStopPress = (stopId: string) => {
    setSelectedStop(stopId);
  };

  const handleBusPress = (busId: string) => {
    // Select bus logic
  };

  return (
    <View style={styles.container}>
      <StatusBar style="light" />
      <LinearGradient
        colors={COLORS.backgroundGradient}
        style={styles.background}
      />
      
      {/* Map Layer */}
      <View style={styles.mapContainer}>
        <BusMap 
          buses={buses} 
          stops={stops} 
          routes={routes} 
          selectedRouteId={selectedRouteId}
          onStopPress={handleStopPress}
          onBusPress={handleBusPress}
        />
        {/* Transparent Overlay for darkening map if needed, or rely on map style */}
      </View>

      {/* Low Data Banner */}
      {isLowDataMode && (
        <View style={[styles.lowDataBanner, { top: insets.top + SPACING.xs }]}>
            <Ionicons name="flash" size={12} color="#000" style={{ marginRight: 6 }} />
            <Text style={styles.lowDataText}>Low Data Mode Active</Text>
        </View>
      )}

      {/* Top Floating Bar */}
      <View style={[styles.topBar, { top: insets.top + (isLowDataMode ? 40 : SPACING.s) }]}>
        <TouchableOpacity style={styles.glassButton} onPress={() => setProfileVisible(true)}>
            <Ionicons name="person-circle-outline" size={28} color="#FFF" />
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.glassPill} onPress={() => setFilterVisible(true)}>
           <View style={[styles.statusDot, { backgroundColor: selectedRouteId ? COLORS.primary : '#AAA' }]} />
           <Text style={styles.statusText}>
               {selectedRouteId ? 'Route Selected' : 'Select Bus'} ▾
           </Text>
        </TouchableOpacity>

        <TouchableOpacity 
            style={[styles.glassButton, isLowDataMode && { backgroundColor: 'rgba(255, 193, 7, 0.3)', borderColor: COLORS.warning }]} 
            onPress={() => setLowDataMode(!isLowDataMode)}
        >
            <Ionicons 
                name={isLowDataMode ? "cellular-outline" : "wifi"} 
                size={20} 
                color={isLowDataMode ? COLORS.warning : "#FFF"} 
            />
        </TouchableOpacity>
      </View>

      {!filterVisible && (
        <BottomSheet onStopClick={handleStopPress} onBusClick={handleBusPress} />
      )}
      
      <ProfileModal visible={profileVisible} onClose={() => setProfileVisible(false)} />
      
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
  background: {
    ...StyleSheet.absoluteFillObject,
  },
  mapContainer: {
    flex: 1,
  },
  lowDataBanner: {
      position: 'absolute',
      left: 0, 
      right: 0,
      height: 30,
      backgroundColor: COLORS.secondary,
      justifyContent: 'center',
      alignItems: 'center',
      zIndex: 20,
      ...SHADOWS.small,
  },
  lowDataText: {
      fontSize: 12,
      fontWeight: 'bold',
      color: '#000',
  },
  topBar: {
    position: 'absolute',
    left: SPACING.m,
    right: SPACING.m,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    zIndex: 10,
  },
  glassButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: 'rgba(255, 255, 255, 0.1)', // Glass
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.2)',
    justifyContent: 'center',
    alignItems: 'center',
    ...SHADOWS.small,
    backdropFilter: 'blur(10px)', // For web support if needed
  },
  glassPill: {
    paddingHorizontal: SPACING.m,
    paddingVertical: SPACING.s,
    backgroundColor: 'rgba(0, 0, 0, 0.6)', // Strongly visible
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.2)',
    ...SHADOWS.small,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  statusText: {
    color: '#fff',
    fontWeight: 'bold',
    fontSize: 14,
    textShadowColor: 'rgba(0,0,0,0.5)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 3,
  },
});
