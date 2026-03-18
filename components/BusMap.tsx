import { Asset } from "expo-asset";
import * as FileSystem from "expo-file-system";
import React, { useEffect, useRef, useState } from "react";
import { ActivityIndicator, StyleSheet, View } from "react-native";
import { WebView } from "react-native-webview";
import { Bus, Route, Stop } from "../constants/mockData";
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
  const webViewRef = useRef<WebView>(null);
  const selectedStopId = useAppStore((state) => state.selectedStopId);
  const driverBus = useAppStore((state) => state.driverBus);
  const [htmlContent, setHtmlContent] = useState<string | null>(null);

  // Load HTML file
  useEffect(() => {
    const loadHtml = async () => {
      try {
        const asset = Asset.fromModule(require("../assets/leaflet.html"));
        await asset.downloadAsync();
        const content = await FileSystem.readAsStringAsync(asset.localUri!);
        setHtmlContent(content);
      } catch (error) {
        console.error("Failed to load map HTML:", error);
      }
    };
    loadHtml();
  }, []);

  // Update Map Data
  useEffect(() => {
    if (webViewRef.current && htmlContent) {
      const data = {
        type: "UPDATE_MAP",
        payload: {
          buses,
          stops,
          routes,
          selectedRouteId,
          driverBus,
        },
      };

      const script = `
        try {
          if (typeof updateMap === 'function') {
            updateMap(${JSON.stringify(data.payload)});
          }
        } catch (e) {
          console.error(e);
        }
      `;
      webViewRef.current.injectJavaScript(script);
    }
  }, [buses, stops, routes, selectedRouteId, driverBus, htmlContent]);

  // Handle Selection Updates (Pan to selected item)
  useEffect(() => {
    if (selectedStopId && webViewRef.current) {
      const stop = stops.find((s) => s.id === selectedStopId);
      if (stop) {
        webViewRef.current.postMessage(
          JSON.stringify({
            type: "CENTER_STOP",
            payload: { lat: stop.lat, lng: stop.lng },
          }),
        );
        // Logic to pan map in JS side would be better handled via direct message if injectJavaScript is flaky for commands
        webViewRef.current.injectJavaScript(`
                if (typeof map !== 'undefined') {
                    map.setView([${stop.lat}, ${stop.lng}], 15, { animate: true });
                }
             `);
      }
    }
  }, [selectedStopId, stops]);

  // Auto-center on Driver Bus if it moves
  useEffect(() => {
    if (driverBus && webViewRef.current) {
      webViewRef.current.injectJavaScript(`
            if (typeof map !== 'undefined') {
                map.setView([${driverBus.currentLat}, ${driverBus.currentLng}], 17, { animate: true });
            }
         `);
    }
  }, [
    driverBus,
    driverBus?.currentLat,
    driverBus?.currentLng,
    driverBus?.heading,
  ]);

  const onMessage = (event: any) => {
    try {
      const data = JSON.parse(event.nativeEvent.data);
      if (data.type === "STOP_PRESS") {
        onStopPress(data.id);
      } else if (data.type === "BUS_PRESS") {
        onBusPress(data.id);
      }
    } catch (e) {
      console.error("Error parsing message from WebView", e);
    }
  };

  if (!htmlContent) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={COLORS.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <WebView
        ref={webViewRef}
        originWhitelist={["*"]}
        source={{ html: htmlContent }}
        style={styles.map}
        onMessage={onMessage}
        javaScriptEnabled={true}
        domStorageEnabled={true}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  map: {
    flex: 1,
    width: "100%",
    height: "100%",
  },
  loadingContainer: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
});
