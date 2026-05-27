import React, { useEffect, useRef } from "react";
import { StyleSheet, View } from "react-native";
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
        mapType="standard"
        userInterfaceStyle="dark"
        customMapStyle={mapStyle}
        pitchEnabled={true}
        rotateEnabled={true}
        zoomEnabled={true}
        scrollEnabled={true}
      >
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

        {stops.map((stop) => {
          const isSelected = stop.id === selectedStopId;
          return (
            <Marker
              key={`stop-${stop.id}`}
              coordinate={{ latitude: stop.lat, longitude: stop.lng }}
              onPress={() => onStopPress(stop.id)}
              tracksViewChanges={false}
            >
              <View
                style={[
                  styles.stopMarker,
                  isSelected && styles.selectedStopMarker,
                ]}
              >
                <Ionicons
                  name="bus-outline"
                  size={12}
                  color={isSelected ? "#0f2027" : COLORS.primary}
                />
              </View>
            </Marker>
          );
        })}

        {activeBuses.map((bus) => (
          <Marker
            key={`bus-${bus.id}`}
            coordinate={{ latitude: bus.currentLat, longitude: bus.currentLng }}
            onPress={() => onBusPress(bus.id)}
            anchor={{ x: 0.5, y: 0.5 }}
            rotation={bus.heading}
            flat={true}
            tracksViewChanges={false}
          >
            <View
              style={[
                styles.busMarker,
                { backgroundColor: bus.routeColor },
              ]}
            >
              <Ionicons name="bus" size={16} color="#FFF" />
            </View>
          </Marker>
        ))}

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
            <View
              style={[
                styles.busMarker,
                {
                  backgroundColor: driverBus.routeColor || COLORS.primary,
                },
              ]}
            >
              <Ionicons name="navigate" size={16} color="#FFF" />
            </View>
          </Marker>
        )}
      </MapView>
    </View>
  );
}

// Dark map style matching the app theme for a premium look
const mapStyle = [
  {
    elementType: "geometry",
    stylers: [{ color: "#242f3e" }],
  },
  {
    elementType: "labels.text.fill",
    stylers: [{ color: "#746855" }],
  },
  {
    elementType: "labels.text.stroke",
    stylers: [{ color: "#242f3e" }],
  },
  {
    featureType: "administrative.locality",
    elementType: "labels.text.fill",
    stylers: [{ color: "#d59563" }],
  },
  {
    featureType: "poi",
    elementType: "labels.text.fill",
    stylers: [{ color: "#d59563" }],
  },
  {
    featureType: "poi.park",
    elementType: "geometry",
    stylers: [{ color: "#263c3f" }],
  },
  {
    featureType: "poi.park",
    elementType: "labels.text.fill",
    stylers: [{ color: "#6b9a76" }],
  },
  {
    featureType: "road",
    elementType: "geometry",
    stylers: [{ color: "#38414e" }],
  },
  {
    featureType: "road",
    elementType: "geometry.stroke",
    stylers: [{ color: "#212a37" }],
  },
  {
    featureType: "road",
    elementType: "labels.text.fill",
    stylers: [{ color: "#9ca5b3" }],
  },
  {
    featureType: "road.highway",
    elementType: "geometry",
    stylers: [{ color: "#746855" }],
  },
  {
    featureType: "road.highway",
    elementType: "geometry.stroke",
    stylers: [{ color: "#1f2835" }],
  },
  {
    featureType: "road.highway",
    elementType: "labels.text.fill",
    stylers: [{ color: "#f3d19c" }],
  },
  {
    featureType: "transit",
    elementType: "geometry",
    stylers: [{ color: "#2f3948" }],
  },
  {
    featureType: "transit.station",
    elementType: "labels.text.fill",
    stylers: [{ color: "#d59563" }],
  },
  {
    featureType: "water",
    elementType: "geometry",
    stylers: [{ color: "#17263c" }],
  },
  {
    featureType: "water",
    elementType: "labels.text.fill",
    stylers: [{ color: "#515c6d" }],
  },
  {
    featureType: "water",
    elementType: "labels.text.stroke",
    stylers: [{ color: "#17263c" }],
  },
];

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  map: {
    ...StyleSheet.absoluteFillObject,
  },
  stopMarker: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: COLORS.background,
    borderWidth: 2,
    borderColor: COLORS.primary,
    justifyContent: "center",
    alignItems: "center",
  },
  selectedStopMarker: {
    backgroundColor: COLORS.primary,
    borderColor: COLORS.white,
    transform: [{ scale: 1.5 }],
    shadowColor: COLORS.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: 10,
    elevation: 5,
  },
  busMarker: {
    width: 36,
    height: 36,
    borderRadius: 18,
    borderWidth: 2,
    borderColor: COLORS.white,
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 4.65,
    elevation: 8,
  },
});
