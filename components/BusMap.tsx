import React, { useEffect, useRef } from "react";
import { StyleSheet, Text, View } from "react-native";
import MapView, { Marker, Polyline, PROVIDER_DEFAULT } from "react-native-maps";
import { Bus, CAMPUS_CENTER, Route, Stop } from "../constants/mockData";
import { COLORS } from "../constants/theme";
import { useAppStore } from "../hooks/useAppStore";

// Stop Icon (Simple circle with inner dot)
const StopMarker = ({ selected }: { selected: boolean }) => (
  <View
    style={[
      styles.stopMarker,
      {
        backgroundColor: selected ? COLORS.primary : COLORS.white,
        transform: [{ scale: selected ? 1.2 : 1 }],
        zIndex: selected ? 10 : 1,
      },
    ]}
  >
    <View
      style={[
        styles.stopInner,
        { backgroundColor: selected ? COLORS.white : COLORS.primary },
      ]}
    />
  </View>
);

const CampusMarker = () => (
  <View style={styles.campusMarker}>
    <Text style={{ fontSize: 12 }}>🏫</Text>
  </View>
);

// Bus Marker (Simple Bus Shape)
const BusMarkerView = ({
  color,
  heading,
  isDriver,
  speed,
}: {
  color: string;
  heading: number;
  isDriver?: boolean;
  speed?: number;
}) => {
  const speedKmh = speed ? Math.round(speed * 3.6) : 0;

  return (
    <View>
      {isDriver && (
        <View style={styles.liveBadge}>
          <Text style={styles.liveText}>LIVE</Text>
        </View>
      )}
      <View
        style={[
          styles.busMarker,
          { backgroundColor: color, transform: [{ rotate: `${heading}deg` }] },
          isDriver && { borderColor: "red", borderWidth: 2 },
        ]}
      >
        <Text style={{ fontSize: 10 }}>{isDriver ? "ME" : "🚌"}</Text>
      </View>
      {isDriver && speed !== undefined && (
        <View style={styles.speedBadge}>
          <Text style={styles.speedText}>{speedKmh} km/h</Text>
        </View>
      )}
    </View>
  );
};

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

  // Filter routes if one is selected
  const displayedRoutes = selectedRouteId
    ? routes.filter((r) => r.id === selectedRouteId)
    : routes;

  const displayedStops = selectedRouteId
    ? stops.filter((s) =>
        s.routes.some((rName) => {
          const route = routes.find((r) => r.id === selectedRouteId);
          return route && s.routes.includes(route.name);
        }),
      )
    : stops;

  let displayedBuses = selectedRouteId
    ? buses.filter((b) => {
        const route = routes.find((r) => r.id === selectedRouteId);
        return route && b.routeName === route.name;
      })
    : buses;

  // Deduplicate buses by ID just in case
  displayedBuses = Array.from(
    new Map(displayedBuses.map((item) => [item.id, item])).values(),
  );

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
          1000,
        );
      }
    }
  }, [selectedStopId, stops]);

  // Auto-center on Driver Bus if it moves
  useEffect(() => {
    if (driverBus && mapRef.current) {
      mapRef.current.animateCamera(
        {
          center: {
            latitude: driverBus.currentLat,
            longitude: driverBus.currentLng,
          },
          heading: driverBus.heading,
          pitch: 0,
          zoom: 17,
        },
        { duration: 500 },
      );
    }
  }, [
    driverBus,
    driverBus?.currentLat,
    driverBus?.currentLng,
    driverBus?.heading,
  ]);

  return (
    <View style={styles.container}>
      <MapView
        ref={mapRef}
        style={styles.map}
        provider={PROVIDER_DEFAULT}
        initialRegion={{
          latitude: 23.2599,
          longitude: 77.4126,
          latitudeDelta: 0.15,
          longitudeDelta: 0.15,
        }}
        showsUserLocation
        showsMyLocationButton={false} // Custom button usually better
      >
        {displayedRoutes.map((route) => (
          <Polyline
            key={route.id}
            coordinates={route.coordinates}
            strokeColor={route.color}
            strokeWidth={4}
          />
        ))}

        {displayedStops.map((stop) => (
          <Marker
            key={stop.id}
            coordinate={{ latitude: stop.lat, longitude: stop.lng }}
            onPress={() => onStopPress(stop.id)}
            anchor={{ x: 0.5, y: 0.5 }}
          >
            <StopMarker selected={selectedStopId === stop.id} />
          </Marker>
        ))}

        {/* Campus / Base Marker */}
        <Marker
          coordinate={{
            latitude: CAMPUS_CENTER.lat,
            longitude: CAMPUS_CENTER.lng,
          }}
          title="SISTEC Campus"
          description="Main Base"
          anchor={{ x: 0.5, y: 0.5 }}
        >
          <CampusMarker />
        </Marker>

        {displayedBuses.map((bus) => (
          <Marker.Animated
            key={`bus-${bus.id}`}
            coordinate={{ latitude: bus.currentLat, longitude: bus.currentLng }}
            onPress={() => onBusPress(bus.id)}
            anchor={{ x: 0.5, y: 0.5 }}
          >
            <View>
              <BusMarkerView
                color={bus.routeColor}
                heading={bus.heading}
                isDriver={!!(driverBus && bus.id === driverBus.id)}
                speed={bus.speed}
              />
            </View>
          </Marker.Animated>
        ))}
      </MapView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  map: {
    width: "100%",
    height: "100%",
  },
  stopMarker: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: "white",
    justifyContent: "center",
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  stopInner: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  campusMarker: {
    backgroundColor: "#fff",
    padding: 5,
    borderRadius: 20,
    borderWidth: 2,
    borderColor: COLORS.primary,
    alignItems: "center",
    justifyContent: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  busMarker: {
    padding: 5,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "white",
    alignItems: "center",
    justifyContent: "center",
  },
  liveBadge: {
    position: "absolute",
    top: -20,
    alignSelf: "center",
    backgroundColor: "red",
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 10,
    zIndex: 10,
    borderWidth: 1,
    borderColor: "white",
  },
  liveText: {
    color: "white",
    fontSize: 8,
    fontWeight: "bold",
  },
  speedBadge: {
    position: "absolute",
    bottom: -18,
    alignSelf: "center",
    backgroundColor: "rgba(0,0,0,0.7)",
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
    zIndex: 10,
    borderWidth: 1,
    borderColor: "white",
  },
  speedText: {
    color: "white",
    fontSize: 9,
    fontWeight: "bold",
  },
});
