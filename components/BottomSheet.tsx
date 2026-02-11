
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Dimensions, FlatList, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { useAnimatedStyle, useSharedValue, withSpring } from 'react-native-reanimated';
import { Bus, Stop } from '../constants/mockData';
import { COLORS, SHADOWS, SPACING } from '../constants/theme';
import { useAppStore } from '../hooks/useAppStore';

const { height: SCREEN_HEIGHT } = Dimensions.get('window');
const MAX_TRANSLATE_Y = -SCREEN_HEIGHT + 100;

interface BottomSheetProps {
  onStopClick: (stopId: string) => void;
  onBusClick: (busId: string) => void;
}

export default function BottomSheet({ onStopClick, onBusClick }: BottomSheetProps) {
  const { buses, stops, selectedRouteId, selectedStopId, driverBus } = useAppStore();
  const [activeTab, setActiveTab] = useState<'Stops' | 'Buses'>('Stops');

  const translateY = useSharedValue(0);
  const context = useSharedValue({ y: 0 });

  const gesture = Gesture.Pan()
    .onStart(() => {
      context.value = { y: translateY.value };
    })
    .onUpdate((event) => {
      translateY.value = event.translationY + context.value.y;
      translateY.value = Math.max(translateY.value, MAX_TRANSLATE_Y);
    })
    .onEnd(() => {
      if (translateY.value < -SCREEN_HEIGHT / 3) {
        translateY.value = withSpring(MAX_TRANSLATE_Y + 150);
      } else if (translateY.value > -100) {
        translateY.value = withSpring(0);
      } else {
        translateY.value = withSpring(-200); // Snap to mid
      }
    });

  const rBottomSheetStyle = useAnimatedStyle(() => {
    return {
      transform: [{ translateY: translateY.value }],
    };
  });
  
  // Snap up when selection changes
  useEffect(() => {
      if (selectedStopId || selectedRouteId) {
          translateY.value = withSpring(-300);
      }
  }, [selectedStopId, selectedRouteId]);

  const filteredStops = useMemo(() => {
      return stops;
  }, [stops, selectedRouteId]);

  const filteredBuses = useMemo(() => {
      let combinedBuses = [...buses];
      if (driverBus) {
          if (!selectedRouteId || driverBus.routeId === selectedRouteId) {
             combinedBuses.push(driverBus);
          }
      }
      return combinedBuses;
  }, [buses, driverBus, selectedRouteId]);

  const handlePress = (callback: () => void) => {
      Haptics.selectionAsync();
      callback();
  }

  const renderStopItem = useCallback(({ item }: { item: Stop }) => (
    <TouchableOpacity style={styles.listItem} onPress={() => handlePress(() => onStopClick(item.id))}>
      <View style={styles.itemIconContainer}>
        <LinearGradient
            colors={['#3498db', '#2980b9']}
            style={styles.itemIconGradient}
        >
            <Text style={{ fontSize: 18 }}>🚏</Text>
        </LinearGradient>
      </View>
      <View style={{ flex: 1 }}>
        <Text style={styles.itemName}>{item.name}</Text>
        <Text style={styles.itemSub}>
            {item.nextArrivals.length > 0 
                ? item.nextArrivals.map(a => `${a.etaMinutes}m (${a.routeName})`).join(', ')
                : 'No upcoming arrivals'}
        </Text>
      </View>
      <View style={[styles.statusBadge, { backgroundColor: 'rgba(46, 204, 113, 0.2)' }]}>
          <Text style={[styles.statusText, { color: '#2ecc71' }]}>Active</Text>
      </View>
    </TouchableOpacity>
  ), [onStopClick]);

  const renderBusItem = useCallback(({ item }: { item: Bus }) => {
    const isDriver = item.id === 'driver-me' || (driverBus && item.id === driverBus.id);
    const speed = item.speed ?? 0;
    const speedKmh = Math.round(speed * 3.6);

    return (
      <TouchableOpacity 
        style={[styles.listItem, isDriver && styles.driverItem]} 
        onPress={() => handlePress(() => onBusClick(item.id))}
      >
         <View style={styles.itemIconContainer}>
            <View style={[styles.busColorDot, { backgroundColor: item.routeColor }]} />
            <Text style={{ fontSize: 18 }}>🚌</Text>
        </View>
        <View style={{ flex: 1 }}>
          <Text style={styles.itemName}>
            {item.routeName} <Text style={{ fontSize: 12, opacity: 0.7 }}>(ID: {item.id})</Text>
          </Text>
          <View style={styles.row}>
              <Text style={styles.itemSub}>
                {isDriver ? 'LIVE TRACKING' : item.status} • {item.occupancyLevel}
              </Text>
              {speed > 0 && (
                  <Text style={[styles.itemSub, { marginLeft: 8, color: COLORS.primary }]}>
                      {speedKmh} km/h
                  </Text>
              )}
          </View>
        </View>
        {isDriver ? (
            <View style={[styles.statusBadge, { backgroundColor: 'rgba(231, 76, 60, 0.2)' }]}>
                <View style={styles.pulseDot} />
                <Text style={[styles.statusText, { color: '#e74c3c' }]}>LIVE</Text>
            </View>
        ) : (
            <Text style={styles.arrowIcon}>›</Text>
        )}
      </TouchableOpacity>
    );
  }, [onBusClick, driverBus]);

  return (
    <GestureDetector gesture={gesture}>
      <Animated.View style={[styles.bottomSheetContainer, rBottomSheetStyle]}>
        <View style={styles.line} />
        
        {/* Tabs */}
        <View style={styles.tabsContainer}>
            <TouchableOpacity 
                style={[styles.tab, activeTab === 'Stops' && styles.activeTab]} 
                onPress={() => {
                    Haptics.selectionAsync();
                    setActiveTab('Stops');
                }}>
                <Text style={[styles.tabText, activeTab === 'Stops' && styles.activeTabText]}>Bus Stops</Text>
            </TouchableOpacity>
            <TouchableOpacity 
                style={[styles.tab, activeTab === 'Buses' && styles.activeTab]} 
                onPress={() => {
                    Haptics.selectionAsync();
                    setActiveTab('Buses');
                }}>
                <Text style={[styles.tabText, activeTab === 'Buses' && styles.activeTabText]}>Active Fleet</Text>
            </TouchableOpacity>
        </View>

        {/* Content */}
        <View style={styles.contentContainer}>
            {activeTab === 'Stops' ? (
                <FlatList
                    data={filteredStops}
                    keyExtractor={item => item.id}
                    renderItem={renderStopItem}
                    contentContainerStyle={{ paddingBottom: 100 }}
                    showsVerticalScrollIndicator={false}
                />
            ) : (
                <FlatList
                    data={filteredBuses}
                    keyExtractor={item => item.id}
                    renderItem={renderBusItem}
                    contentContainerStyle={{ paddingBottom: 100 }}
                    showsVerticalScrollIndicator={false}
                />
            )}
        </View>
      </Animated.View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  bottomSheetContainer: {
    height: SCREEN_HEIGHT,
    width: '100%',
    backgroundColor: '#1E293B',
    position: 'absolute',
    top: SCREEN_HEIGHT - 100,
    borderTopLeftRadius: 30,
    borderTopRightRadius: 30,
    ...SHADOWS.medium,
    paddingHorizontal: SPACING.l,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.1)',
  },
  line: {
    width: 60,
    height: 5,
    backgroundColor: 'rgba(255,255,255,0.2)',
    alignSelf: 'center',
    marginVertical: SPACING.m,
    borderRadius: 3,
  },
  tabsContainer: {
      flexDirection: 'row',
      marginBottom: SPACING.m,
      borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  tab: {
      paddingVertical: SPACING.m,
      marginRight: SPACING.xl,
  },
  activeTab: {
      borderBottomWidth: 3,
      borderBottomColor: COLORS.primary,
  },
  tabText: {
      fontSize: 16,
      color: COLORS.textLight,
      fontWeight: '600',
  },
  activeTabText: {
      color: '#FFF',
      fontWeight: 'bold',
  },
  contentContainer: {
      flex: 1,
  },
  listItem: {
      flexDirection: 'row',
      alignItems: 'center',
      padding: SPACING.m,
      backgroundColor: 'rgba(255,255,255,0.03)',
      marginBottom: SPACING.s,
      borderRadius: 16,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.05)',
  },
  driverItem: {
      backgroundColor: 'rgba(46, 204, 113, 0.05)',
      borderColor: 'rgba(46, 204, 113, 0.2)',
  },
  itemIconContainer: {
      width: 48,
      height: 48,
      justifyContent: 'center',
      alignItems: 'center',
      marginRight: SPACING.m,
  },
  itemIconGradient: {
      width: 40,
      height: 40,
      borderRadius: 20,
      justifyContent: 'center',
      alignItems: 'center',
  },
  busColorDot: {
      position: 'absolute',
      width: 48,
      height: 48,
      borderRadius: 24,
      opacity: 0.2,
  },
  itemName: {
      fontSize: 16,
      fontWeight: 'bold',
      color: COLORS.text,
      marginBottom: 2,
  },
  itemSub: {
      fontSize: 12,
      color: COLORS.textSecondary,
  },
  row: {
      flexDirection: 'row',
      alignItems: 'center',
  },
  statusBadge: {
      paddingHorizontal: 10,
      paddingVertical: 5,
      borderRadius: 20,
      flexDirection: 'row',
      alignItems: 'center',
  },
  statusText: {
      fontSize: 10,
      fontWeight: 'bold',
      textTransform: 'uppercase',
  },
  pulseDot: {
      width: 6,
      height: 6,
      borderRadius: 3,
      backgroundColor: '#e74c3c',
      marginRight: 6,
  },
  arrowIcon: {
      fontSize: 20,
      color: COLORS.textLight,
      opacity: 0.5,
  }
});

