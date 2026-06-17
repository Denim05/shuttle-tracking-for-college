import React, { useEffect, useRef, useState, useMemo } from "react";
import { StyleSheet, View, TouchableOpacity, Text } from "react-native";
import MapView, { Marker, Polyline, PROVIDER_GOOGLE } from "react-native-maps";
import { Ionicons } from "@expo/vector-icons";
import { Bus, Route, Stop, CAMPUS_CENTER } from "../constants/mockData";
import { COLORS } from "../constants/theme";
import { useAppStore } from "../hooks/useAppStore";

interface BusMapProps {
  buses: Bus[];
  stops: Stop[];
  routes: Route[];
  selectedRouteId: string | null;
  onStopPress: (stopId: string) => void;
  onBusPress: (busId: string) => void;
}

type MapTheme = "sleekDark" | "cyberpunk" | "classicSilver";

export default function BusMap({
  buses,
  stops,
  routes,
  selectedRouteId,
  onStopPress,
  onBusPress,
}: BusMapProps) {
  const mapRef = useRef<MapView>(null);
  const selectedStopId = useAppStore((state) => state.selectedStopId);
  const driverBus = useAppStore((state) => state.driverBus);

  // Map type state: standard, satellite, or hybrid
  const [mapType, setMapType] = useState<"standard" | "satellite" | "hybrid">("standard");
  const [mapTheme, setMapTheme] = useState<MapTheme>("sleekDark");

  // Center on selected stop
  useEffect(() => {
    if (selectedStopId && mapRef.current) {
      const stop = stops.find((s) => s.id === selectedStopId);
      if (stop) {
        mapRef.current.animateToRegion(
          {
            latitude: stop.lat,
            longitude: stop.lng,
            latitudeDelta: 0.005,
            longitudeDelta: 0.005,
          },
          1000
        );
      }
    }
  }, [selectedStopId, stops]);

  // Center on driver bus
  useEffect(() => {
    if (driverBus && mapRef.current) {
      mapRef.current.animateToRegion(
        {
          latitude: driverBus.currentLat,
          longitude: driverBus.currentLng,
          latitudeDelta: 0.005,
          longitudeDelta: 0.005,
        },
        1000
      );
    }
  }, [driverBus, driverBus?.currentLat, driverBus?.currentLng]);

  const activeRoutes = selectedRouteId
    ? routes.filter((r) => r.id === selectedRouteId)
    : routes;

  const activeBuses = selectedRouteId
    ? buses.filter((b) => b.routeId === selectedRouteId)
    : buses;

  // Deduplicate activeBuses by busNumber so we only render one marker per physical vehicle on the map.
  // Prioritize active/online buses over offline ones if duplicates exist.
  const uniqueBuses = useMemo(() => {
    const seen = new Map<string, Bus>();
    for (const bus of activeBuses) {
      // Uniquely identify the physical bus using busNumber or a normalized bus display number from routeName
      const key = (bus.busNumber && bus.busNumber !== 'N/A')
        ? bus.busNumber
        : (bus.routeName.match(/Bus no:\s*([^\s)]+)/)?.[1] 
           || bus.routeName.match(/Bus\s+(\d+)/)?.[1] 
           || bus.id);

      const existing = seen.get(key);
      if (!existing) {
        seen.set(key, bus);
      } else {
        // Keep the online/moving bus instead of the offline/static one
        if (bus.status !== 'Offline' && existing.status === 'Offline') {
          seen.set(key, bus);
        }
      }
    }
    return Array.from(seen.values());
  }, [activeBuses]);

  const toggleMapType = () => {
    setMapType((prev) => (prev === "standard" ? "hybrid" : "standard"));
  };

  const cycleTheme = () => {
    setMapTheme((prev) => {
      if (prev === "sleekDark") return "cyberpunk";
      if (prev === "cyberpunk") return "classicSilver";
      return "sleekDark";
    });
  };

  const currentMapStyle = useMemo(() => {
    if (mapType !== "standard") return []; // No styles on satellite/hybrid
    switch (mapTheme) {
      case "cyberpunk":
        return cyberpunkTheme;
      case "classicSilver":
        return classicSilverTheme;
      case "sleekDark":
      default:
        return sleekDarkTheme;
    }
  }, [mapTheme, mapType]);

  return (
    <View style={styles.container}>
      <MapView
        ref={mapRef}
        style={styles.map}
        provider={PROVIDER_GOOGLE}
        initialRegion={{
          latitude: CAMPUS_CENTER.lat,
          longitude: CAMPUS_CENTER.lng,
          latitudeDelta: 0.05,
          longitudeDelta: 0.05,
        }}
        showsUserLocation
        showsMyLocationButton
        mapType={mapType}
        userInterfaceStyle="dark"
        customMapStyle={currentMapStyle}
        pitchEnabled={true}
        rotateEnabled={true}
        zoomEnabled={true}
        scrollEnabled={true}
      >
        {/* Render Routes */}
        {activeRoutes.map((route) => (
          <Polyline
            key={route.id}
            coordinates={route.coordinates}
            strokeColor={route.color}
            strokeWidth={4}
            lineJoin="round"
            lineCap="round"
          />
        ))}

        {/* Render Stops with Glowing Halos */}
        {stops.map((stop) => {
          const isSelected = stop.id === selectedStopId;
          return (
            <Marker
              key={`stop-${stop.id}`}
              coordinate={{ latitude: stop.lat, longitude: stop.lng }}
              onPress={() => onStopPress(stop.id)}
              tracksViewChanges={false}
            >
              <View style={styles.stopWrapper}>
                {/* Glow ring under stop marker */}
                <View style={[
                  styles.stopGlowRing,
                  isSelected ? styles.selectedStopGlow : { borderColor: 'rgba(76, 205, 196, 0.15)' }
                ]} />
                <View
                  style={[
                    styles.stopMarker,
                    isSelected && styles.selectedStopMarker,
                  ]}
                >
                  <Ionicons
                    name="bus"
                    size={isSelected ? 14 : 11}
                    color={isSelected ? "#000" : COLORS.primary}
                  />
                </View>
              </View>
            </Marker>
          );
        })}

        {/* Render Unique Buses */}
        {uniqueBuses.map((bus) => {
          const isOffline = bus.status === "Offline";
          return (
            <Marker
              key={`bus-${bus.id}`}
              coordinate={{ latitude: bus.currentLat, longitude: bus.currentLng }}
              onPress={() => onBusPress(bus.id)}
              anchor={{ x: 0.5, y: 0.5 }}
              rotation={bus.heading}
              flat={true}
              tracksViewChanges={false}
            >
              <View style={styles.busWrapper}>
                {/* Pulse outer aura for online buses */}
                {!isOffline && (
                  <View style={[
                    styles.busPulseAura,
                    { borderColor: bus.routeColor || COLORS.primary }
                  ]} />
                )}
                <View
                  style={[
                    styles.busMarker,
                    { 
                      backgroundColor: isOffline ? "#4A5568" : (bus.routeColor || COLORS.primary),
                      borderColor: isOffline ? "#A0AEC0" : "#FFF"
                    },
                  ]}
                >
                  <Ionicons 
                    name={isOffline ? "bus" : "navigate"} 
                    size={isOffline ? 15 : 17} 
                    color="#FFF" 
                  />
                </View>
              </View>
            </Marker>
          );
        })}

        {/* Driver self-location marker */}
        {driverBus && (
          <Marker
            key="driver-bus"
            coordinate={{
              latitude: driverBus.currentLat,
              longitude: driverBus.currentLng,
            }}
            anchor={{ x: 0.5, y: 0.5 }}
            rotation={driverBus.heading || 0}
            flat={true}
            tracksViewChanges={false}
          >
            <View style={styles.busWrapper}>
              <View style={[styles.busPulseAura, { borderColor: COLORS.primary, transform: [{ scale: 1.2 }] }]} />
              <View
                style={[
                  styles.busMarker,
                  {
                    backgroundColor: driverBus.routeColor || COLORS.primary,
                  },
                ]}
              >
                <Ionicons name="navigate" size={17} color="#FFF" />
              </View>
            </View>
          </Marker>
        )}
      </MapView>

      {/* Premium Map Controls Overlay */}
      <View style={styles.controlsContainer}>
        <TouchableOpacity 
          style={styles.controlBtn} 
          onPress={toggleMapType}
          activeOpacity={0.85}
        >
          <Ionicons 
            name={mapType === "standard" ? "earth-outline" : "map-outline"} 
            size={18} 
            color="#FFF" 
          />
          <Text style={styles.controlText}>
            {mapType === "standard" ? "Satellite" : "Map"}
          </Text>
        </TouchableOpacity>
        
        {mapType === "standard" && (
          <TouchableOpacity 
            style={styles.controlBtn} 
            onPress={cycleTheme}
            activeOpacity={0.85}
          >
            <Ionicons name="color-palette-outline" size={18} color="#FFF" />
            <Text style={styles.controlText}>Theme</Text>
          </TouchableOpacity>
        )}
      </View>
    </View>
  );
}

// ─── PREMIUM MAP THEMES ──────────────────────────────────────────────────────

const sleekDarkTheme = [
  { elementType: "geometry", stylers: [{ color: "#1E293B" }] },
  { elementType: "labels.text.fill", stylers: [{ color: "#94A3B8" }] },
  { elementType: "labels.text.stroke", stylers: [{ color: "#0F172A" }] },
  { featureType: "administrative.locality", elementType: "labels.text.fill", stylers: [{ color: "#F1F5F9" }] },
  { featureType: "poi", elementType: "labels.text.fill", stylers: [{ color: "#38BDF8" }] },
  { featureType: "poi.park", elementType: "geometry", stylers: [{ color: "#0F172A" }] },
  { featureType: "road", elementType: "geometry", stylers: [{ color: "#334155" }] },
  { featureType: "road", elementType: "geometry.stroke", stylers: [{ color: "#1E293B" }] },
  { featureType: "road", elementType: "labels.text.fill", stylers: [{ color: "#64748B" }] },
  { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#475569" }] },
  { featureType: "road.highway", elementType: "geometry.stroke", stylers: [{ color: "#0F172A" }] },
  { featureType: "transit", elementType: "geometry", stylers: [{ color: "#1E293B" }] },
  { featureType: "water", elementType: "geometry", stylers: [{ color: "#0F172A" }] },
];

const cyberpunkTheme = [
  { elementType: "geometry", stylers: [{ color: "#0C0F17" }] },
  { elementType: "labels.text.fill", stylers: [{ color: "#00F0FF" }] },
  { elementType: "labels.text.stroke", stylers: [{ color: "#0C0F17" }] },
  { featureType: "poi", elementType: "geometry", stylers: [{ color: "#121824" }] },
  { featureType: "poi.park", elementType: "geometry", stylers: [{ color: "#1B172E" }] },
  { featureType: "road", elementType: "geometry", stylers: [{ color: "#1B2234" }] },
  { featureType: "road", elementType: "geometry.stroke", stylers: [{ color: "#FF007F" }] },
  { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#252F47" }] },
  { featureType: "road.highway", elementType: "geometry.stroke", stylers: [{ color: "#00F0FF" }] },
  { featureType: "transit", elementType: "geometry", stylers: [{ color: "#121824" }] },
  { featureType: "water", elementType: "geometry", stylers: [{ color: "#04060A" }] },
];

const classicSilverTheme = [
  { elementType: "geometry", stylers: [{ color: "#F5F5F7" }] },
  { elementType: "labels.text.fill", stylers: [{ color: "#616161" }] },
  { elementType: "labels.text.stroke", stylers: [{ color: "#F5F5F7" }] },
  { featureType: "poi", elementType: "geometry", stylers: [{ color: "#EEEEEE" }] },
  { featureType: "road", elementType: "geometry", stylers: [{ color: "#FFFFFF" }] },
  { featureType: "road", elementType: "geometry.stroke", stylers: [{ color: "#E0E0E0" }] },
  { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#F1F1F1" }] },
  { featureType: "water", elementType: "geometry", stylers: [{ color: "#C9E2F2" }] },
];

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  map: {
    ...StyleSheet.absoluteFillObject,
  },
  
  // Stops Custom Pulsing / Glow styling
  stopWrapper: {
    width: 36,
    height: 36,
    justifyContent: "center",
    alignItems: "center",
  },
  stopGlowRing: {
    position: "absolute",
    width: 28,
    height: 28,
    borderRadius: 14,
    borderWidth: 2,
    backgroundColor: "transparent",
  },
  selectedStopGlow: {
    borderColor: COLORS.primary,
    backgroundColor: "rgba(76, 205, 196, 0.15)",
  },
  stopMarker: {
    width: 20,
    height: 20,
    borderRadius: 10,
    backgroundColor: COLORS.background,
    borderWidth: 2.5,
    borderColor: COLORS.primary,
    justifyContent: "center",
    alignItems: "center",
    elevation: 3,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1.41,
  },
  selectedStopMarker: {
    backgroundColor: COLORS.primary,
    borderColor: COLORS.white,
    transform: [{ scale: 1.2 }],
    elevation: 6,
    shadowColor: COLORS.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 5,
  },

  // Buses Custom styling
  busWrapper: {
    width: 44,
    height: 44,
    justifyContent: "center",
    alignItems: "center",
  },
  busPulseAura: {
    position: "absolute",
    width: 40,
    height: 40,
    borderRadius: 20,
    borderWidth: 1.5,
    backgroundColor: "rgba(255, 255, 255, 0.1)",
    opacity: 0.6,
  },
  busMarker: {
    width: 32,
    height: 32,
    borderRadius: 16,
    borderWidth: 2,
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.35,
    shadowRadius: 4.65,
    elevation: 8,
  },

  // Floating controls
  controlsContainer: {
    position: "absolute",
    top: 110,
    right: 16,
    flexDirection: "column",
    gap: 8,
    zIndex: 100,
  },
  controlBtn: {
    width: 54,
    height: 54,
    borderRadius: 16,
    backgroundColor: "rgba(15, 23, 42, 0.85)",
    borderWidth: 1,
    borderColor: "rgba(255, 255, 255, 0.12)",
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 5,
    elevation: 6,
  },
  controlText: {
    fontSize: 8,
    fontWeight: "900",
    color: "#FFF",
    marginTop: 2,
    textTransform: "uppercase",
    letterSpacing: 0.5,
  },
});
