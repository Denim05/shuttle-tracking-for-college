
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import * as Location from 'expo-location';
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import ProfileModal from '../../components/ProfileModal';
import { COLORS, SHADOWS, SPACING } from '../../constants/theme';
import { useAppStore } from '../../hooks/useAppStore';

export default function DriverScreen() {
  const router = useRouter();
  const { startDriving, stopDriving, isDriverMode, username, driverBus, socketConnected } = useAppStore();
  const [selectedBusNumber, setSelectedBusNumber] = useState<number | null>(null);
  const [profileVisible, setProfileVisible] = useState(false);

  const handleBusSelect = (num: number) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setSelectedBusNumber(num);
  };

  const handleStartDriving = async () => {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    if (!selectedBusNumber) {
        Alert.alert('Select Bus', 'Please select a bus number first.');
        return;
    }

    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission Denied', 'Permission to access location was denied');
      return;
    }

    startDriving(selectedBusNumber);
  };

  const handleStopDriving = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    stopDriving();
  };

  return (
    <View style={styles.container}>
      <LinearGradient
        colors={['#0f2027', '#203a43', '#2c5364']}
        style={StyleSheet.absoluteFillObject}
      />
      
      {/* Dev Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => setProfileVisible(true)}>
            <Text style={styles.title}>Driver Console</Text>
            <Text style={styles.welcomeText}>
                OP: {username || 'Anon'} | ID: {driverBus?.id || 'N/A'}
            </Text>
        </TouchableOpacity>
        <View style={[styles.badge, { backgroundColor: socketConnected ? 'rgba(76, 205, 196, 0.2)' : 'rgba(255, 107, 107, 0.2)' }]}>
            <View style={[styles.statusDot, { backgroundColor: socketConnected ? '#4ECDC4' : '#FF6B6B' }]} />
            <Text style={[styles.statusText, { color: socketConnected ? '#4ECDC4' : '#FF6B6B' }]}>
                {socketConnected ? 'ONLINE' : 'OFFLINE'}
            </Text>
        </View>
      </View>
      
      <ProfileModal visible={profileVisible} onClose={() => setProfileVisible(false)} />
      
      {!isDriverMode ? (
          <ScrollView contentContainerStyle={styles.content}>
            <Text style={styles.sectionTitle}>DEPLOYMENT TARGET</Text>
            
            <View style={styles.busGrid}>
                {Array.from({ length: 7 }, (_, i) => i + 1).map((num) => (
                    <TouchableOpacity 
                        key={num} 
                        style={[
                            styles.busCard, 
                            selectedBusNumber === num && styles.busCardActive
                        ]}
                        onPress={() => handleBusSelect(num)}
                        activeOpacity={0.7}
                    >
                        <LinearGradient
                            colors={selectedBusNumber === num ? [COLORS.primary, '#2ecc71'] : ['rgba(255,255,255,0.05)', 'rgba(255,255,255,0.02)']}
                            style={StyleSheet.absoluteFillObject}
                            start={{x:0, y:0}}
                            end={{x:1, y:1}}
                        />
                        <Text style={[
                            styles.busNumber,
                            selectedBusNumber === num && styles.busNumberActive
                        ]}>{num}</Text>
                        <Text style={[styles.busLabel, selectedBusNumber === num && { color: 'rgba(255,255,255,0.8)' }]}>BUS UNIT</Text>
                    </TouchableOpacity>
                ))}
            </View>
            
            <TouchableOpacity 
                activeOpacity={0.8}
                onPress={handleStartDriving}
                style={styles.actionButtonContainer}
            >
                <LinearGradient
                    colors={[COLORS.primaryDark, COLORS.primary]}
                    start={{ x: 0, y: 0 }}
                    end={{ x: 1, y: 0 }}
                    style={styles.actionButton}
                >
                    <Text style={styles.actionButtonText}>INITIATE BROADCASTING</Text>
                </LinearGradient>
            </TouchableOpacity>
          </ScrollView>
      ) : (
          <View style={styles.content}>
              {/* Nerd Stats Overlay */}
              <View style={styles.statsPanel}>
                  <View style={styles.statsHeader}>
                      <Text style={styles.statsTitle}>SYSTEM TELEMETRY</Text>
                      <View style={styles.liveIndicator}>
                          <View style={styles.pulseDot} />
                          <Text style={styles.liveText}>LIVE</Text>
                      </View>
                  </View>
                  
                  <View style={styles.gridRow}>
                     <View style={styles.statItem}>
                         <Text style={styles.statLabel}>SPD (km/h)</Text>
                         <Text style={styles.statValue}>{driverBus?.speed ? Math.round(driverBus.speed * 3.6) : 0}</Text>
                     </View>
                     <View style={styles.statItem}>
                         <Text style={styles.statLabel}>HDG</Text>
                         <Text style={styles.statValue}>{Math.round(driverBus?.heading || 0)}°</Text>
                     </View>
                     <View style={styles.statItem}>
                         <Text style={styles.statLabel}>LAT</Text>
                         <Text style={styles.statValue}>{driverBus?.currentLat.toFixed(4)}</Text>
                     </View>
                  </View>
                  
                  <View style={styles.codeBlock}>
                      <Text style={styles.codeText}>{`> Uplink: ${socketConnected ? 'ESTABLISHED' : 'SEARCHING...'}`}</Text>
                      <Text style={styles.codeText}>{`> Unit ID: ${driverBus?.id}`}</Text>
                      <Text style={styles.codeText}>{`> Latency: ~${Math.floor(Math.random() * 20 + 10)}ms`}</Text>
                  </View>
              </View>

              <TouchableOpacity 
                style={styles.terminateButton}
                onPress={handleStopDriving}
            >
                <Text style={styles.terminateText}>TERMINATE SESSION</Text>
            </TouchableOpacity>
          </View>
      )}

      <TouchableOpacity style={styles.backButton} onPress={() => router.back()}>
          <Ionicons name="log-out-outline" size={20} color="rgba(255,255,255,0.5)" style={{ marginRight: 6 }} />
          <Text style={styles.backText}>END SESSION</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: 60,
    paddingHorizontal: SPACING.l,
    backgroundColor: '#0f2027',
  },
  header: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      marginBottom: SPACING.xl,
      borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.1)',
      paddingBottom: SPACING.m,
  },
  title: {
      fontSize: 24,
      fontWeight: '900',
      color: COLORS.text,
      letterSpacing: 1,
  },
  welcomeText: {
      fontSize: 12, 
      color: COLORS.textSecondary,
      fontFamily: 'monospace',
  },
  badge: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 8,
      paddingVertical: 4,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
  },
  statusDot: {
      width: 6,
      height: 6,
      borderRadius: 3,
      marginRight: 6,
  },
  statusText: {
      fontSize: 10,
      fontWeight: 'bold',
  },
  content: {
      flex: 1,
      alignItems: 'center',
  },
  sectionTitle: {
      color: COLORS.textLight,
      fontSize: 12,
      fontWeight: 'bold',
      letterSpacing: 2,
      marginBottom: SPACING.m,
      alignSelf: 'flex-start',
  },
  busGrid: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      justifyContent: 'center',
      gap: SPACING.m,
      width: '100%',
  },
  busCard: {
      width: 100,
      height: 100,
      borderRadius: 20,
      justifyContent: 'center',
      alignItems: 'center',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
      backgroundColor: 'rgba(255,255,255,0.02)',
      overflow: 'hidden',
  },
  busCardActive: {
      borderColor: COLORS.primary,
      transform: [{ scale: 1.05 }],
  },
  busNumber: {
      fontSize: 32,
      fontWeight: 'bold',
      color: 'rgba(255,255,255,0.5)',
      zIndex: 1,
  },
  busNumberActive: {
      color: '#FFF',
  },
  busLabel: {
      fontSize: 8,
      color: 'rgba(255,255,255,0.3)',
      fontWeight: 'bold',
      marginTop: 4,
      zIndex: 1,
  },
  actionButtonContainer: {
      marginTop: SPACING.xl * 2,
      borderRadius: 8,
      width: '100%',
      ...SHADOWS.glow,
  },
  actionButton: {
      paddingVertical: SPACING.l,
      borderRadius: 8,
      alignItems: 'center',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.2)',
  },
  actionButtonText: {
      color: '#FFF',
      fontSize: 16,
      fontWeight: '900',
      letterSpacing: 2,
  },
  statsPanel: {
      width: '100%',
      backgroundColor: 'rgba(0,0,0,0.3)',
      borderRadius: 12,
      borderWidth: 1,
      borderColor: 'rgba(78, 205, 196, 0.3)',
      padding: SPACING.m,
      marginBottom: SPACING.xl,
  },
  statsHeader: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      marginBottom: SPACING.m,
      borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.1)',
      paddingBottom: SPACING.s,
  },
  statsTitle: {
      color: '#4ECDC4',
      fontSize: 12,
      fontWeight: 'bold',
      letterSpacing: 1,
  },
  liveIndicator: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: 'rgba(255, 0, 0, 0.2)',
      paddingHorizontal: 6,
      paddingVertical: 2,
      borderRadius: 4,
  },
  pulseDot: {
      width: 6,
      height: 6,
      borderRadius: 3,
      backgroundColor: 'red',
      marginRight: 4,
  },
  liveText: {
      color: 'red',
      fontSize: 10,
      fontWeight: 'bold',
  },
  gridRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      marginBottom: SPACING.m,
  },
  statItem: {
      alignItems: 'center',
      flex: 1,
  },
  statLabel: {
      color: 'rgba(255,255,255,0.4)',
      fontSize: 10,
      fontWeight: '700',
  },
  statValue: {
      color: '#FFF',
      fontSize: 18,
      fontWeight: 'bold',
      fontFamily: 'monospace',
  },
  codeBlock: {
      backgroundColor: 'rgba(0,0,0,0.5)',
      padding: SPACING.s,
      borderRadius: 4,
  },
  codeText: {
      color: '#00FF00',
      fontFamily: 'monospace',
      fontSize: 10,
      opacity: 0.8,
  },
  terminateButton: {
      width: '100%',
      padding: SPACING.l,
      backgroundColor: 'rgba(255, 0, 0, 0.1)',
      borderWidth: 1,
      borderColor: 'red',
      borderRadius: 8,
      alignItems: 'center',
  },
  terminateText: {
      color: 'red',
      fontWeight: 'bold',
      letterSpacing: 1,
  },
  backButton: {
      position: 'absolute',
      bottom: SPACING.xl,
      left: SPACING.l,
  },
  backText: {
      color: 'rgba(255,255,255,0.5)',
      fontSize: 14,
      fontWeight: 'bold',
  }
});

