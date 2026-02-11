import { Ionicons } from '@expo/vector-icons';
import React, { useMemo, useState } from 'react';
import { Modal, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { COLORS, SHADOWS, SPACING } from '../constants/theme';
import { useAppStore } from '../hooks/useAppStore';

interface RouteSelectionSheetProps {
  visible: boolean;
  onClose: () => void;
}

export default function RouteSelectionSheet({ visible, onClose }: RouteSelectionSheetProps) {
  const { routes, stops, setSelectedRoute, setSelectedStop, selectedRouteId, selectedStopId } = useAppStore();
  
  // Local state for temporary selection before confirming
  const [tempRouteId, setTempRouteId] = useState<string | null>(selectedRouteId);
  const [tempStopId, setTempStopId] = useState<string | null>(selectedStopId);

  const handleRouteSelect = (routeId: string) => {
    setTempRouteId(routeId);
    setTempStopId(null); // Reset stop when route changes
  };

  const handleApply = () => {
    setSelectedRoute(tempRouteId);
    setSelectedStop(tempStopId);
    onClose();
  };

  const handleClear = () => {
      setTempRouteId(null);
      setTempStopId(null);
      setSelectedRoute(null);
      setSelectedStop(null);
      onClose();
  };

  // Filter stops based on selected temp route
  const filteredStops = useMemo(() => {
    if (!tempRouteId) return [];
    const route = routes.find(r => r.id === tempRouteId);
    if (!route) return [];
    
    // Determine stops that belong to this route
    // Logic: Stop has "routes" array which contains route names
    return stops.filter(s => s.routes.includes(route.name));
  }, [routes, stops, tempRouteId]);

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <View style={styles.overlay}>
        {/* Removed BlurView, using solid semi-transparent background */}
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={styles.title}>Filter Map</Text>
                <TouchableOpacity onPress={onClose}>
                    <Ionicons name="close" size={24} color={COLORS.text} />
                </TouchableOpacity>
            </View>

            <ScrollView contentContainerStyle={styles.content}>
                {/* Route Selection */}
                <Text style={styles.sectionLabel}>SELECT ROUTE</Text>
                <View style={styles.chipContainer}>
                    {routes.map(route => (
                        <TouchableOpacity
                            key={route.id}
                            style={[
                                styles.chip,
                                tempRouteId === route.id && { backgroundColor: route.color, borderColor: route.color }
                            ]}
                            onPress={() => handleRouteSelect(route.id)}
                        >
                            <Text style={[
                                styles.chipText,
                                tempRouteId === route.id && { color: '#FFF', fontWeight: 'bold' }
                            ]}>{route.name}</Text>
                        </TouchableOpacity>
                    ))}
                </View>

                {/* Stop Selection */}
                {tempRouteId && (
                    <>
                        <Text style={styles.sectionLabel}>SELECT STOP</Text>
                        <View style={styles.chipContainer}>
                            {filteredStops.map(stop => (
                                <TouchableOpacity
                                    key={stop.id}
                                    style={[
                                        styles.chip,
                                        tempStopId === stop.id && styles.chipActive
                                    ]}
                                    onPress={() => setTempStopId(stop.id)}
                                >
                                    <Text style={[
                                        styles.chipText,
                                        tempStopId === stop.id && styles.chipTextActive
                                    ]}>{stop.name}</Text>
                                </TouchableOpacity>
                            ))}
                        </View>
                    </>
                )}
            </ScrollView>

            <View style={styles.footer}>
                <TouchableOpacity style={styles.clearButton} onPress={handleClear}>
                    <Text style={styles.clearButtonText}>Clear</Text>
                </TouchableOpacity>
                <TouchableOpacity style={styles.applyButton} onPress={handleApply}>
                    <Text style={styles.applyButtonText}>Show Results</Text>
                </TouchableOpacity>
            </View>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.85)', // Darker background for better focus
    justifyContent: 'flex-end',
  },
  container: {
    backgroundColor: COLORS.card,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    maxHeight: '80%',
    paddingBottom: 40,
    ...SHADOWS.medium,
  },
  header: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: SPACING.l,
      borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.1)',
  },
  title: {
      fontSize: 18,
      fontWeight: 'bold',
      color: COLORS.text,
  },
  content: {
      padding: SPACING.l,
  },
  sectionLabel: {
      color: COLORS.textSecondary,
      fontSize: 12,
      fontWeight: 'bold',
      marginBottom: SPACING.m,
      marginTop: SPACING.m,
  },
  chipContainer: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: SPACING.s,
  },
  chip: {
      paddingHorizontal: 16,
      paddingVertical: 10,
      borderRadius: 20,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.2)',
      backgroundColor: 'rgba(255,255,255,0.05)',
  },
  chipActive: {
      backgroundColor: COLORS.primary,
      borderColor: COLORS.primary,
  },
  chipText: {
      color: COLORS.text,
      fontSize: 14,
  },
  chipTextActive: {
      color: '#000',
      fontWeight: 'bold',
  },
  footer: {
      padding: SPACING.l,
      flexDirection: 'row',
      gap: SPACING.m,
      borderTopWidth: 1,
      borderTopColor: 'rgba(255,255,255,0.1)',
  },
  clearButton: {
      flex: 1,
      padding: SPACING.m,
      alignItems: 'center',
      borderRadius: 8,
      borderWidth: 1,
      borderColor: COLORS.error,
  },
  clearButtonText: {
      color: COLORS.error,
      fontWeight: 'bold',
  },
  applyButton: {
      flex: 2,
      padding: SPACING.m,
      backgroundColor: COLORS.primary,
      alignItems: 'center',
      borderRadius: 8,
  },
  applyButtonText: {
      color: '#000',
      fontWeight: 'bold',
      fontSize: 16,
  }
});
