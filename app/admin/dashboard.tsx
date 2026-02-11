

import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import AdminUserModal from '../../components/AdminUserModal';
import BusMap from '../../components/BusMap';
import ProfileModal from '../../components/ProfileModal';
import { COLORS, SPACING } from '../../constants/theme';
import { API_URL, useAppStore } from '../../hooks/useAppStore';

// Temporary type interfaces for UI
interface Entity { id: string; name: string; type: string; }

export default function AdminDashboard() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { buses, routes, stops, fetchInitialData, socketConnected } = useAppStore();
  
  const [modalVisible, setModalVisible] = useState(false);
  const [profileVisible, setProfileVisible] = useState(false);
  const [entities, setEntities] = useState<Entity[]>([
      { id: '1', name: 'Manager John', type: 'Manager' }, // You can replace this with real fetch later
      { id: '2', name: 'Driver Mike', type: 'Driver' },
      { id: '3', name: 'User Alice', type: 'User' },
  ]);

  useEffect(() => {
    fetchInitialData();
  }, [fetchInitialData]);

  const handleCreated = async (type: string, data: any) => {
      console.log('Creating', type, data);
      
      const endpoint = type === 'user' ? 'users' : type === 'manager' ? 'managers' : 'drivers';
      
      try {
        const response = await fetch(`${API_URL}/api/${endpoint}`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(data)
        });
        
        if (response.ok) {
            const newEntity = await response.json();
            Alert.alert('Success', `${type} created successfully`);
            setEntities(prev => [...prev, { 
                id: newEntity._id || Date.now().toString(), 
                name: newEntity.username || newEntity.name || 'Unknown', 
                type: type.charAt(0).toUpperCase() + type.slice(1) 
            }]);
        } else {
            Alert.alert('Error', 'Failed to create entity');
        }
      } catch (e: any) {
        Alert.alert('Network Error', e.message);
      }
  };

  const delayedBuses = buses.filter(b => b.status === 'Delayed');
  const onTimePercentage = Math.round(((buses.length - delayedBuses.length) / buses.length) * 100) || 100;

  const renderStatCard = (title: string, value: string | number, sub: string, color: string = 'rgba(255,255,255,0.1)') => (
    <View style={[styles.statCard, { backgroundColor: color }]}>
        <Text style={styles.statValue}>{value}</Text>
        <Text style={styles.statTitle}>{title}</Text>
        <Text style={styles.statSub}>{sub}</Text>
    </View>
  );

  return (
    <View style={styles.container}>
      <LinearGradient
        colors={['#0f2027', '#203a43', '#2c5364']}
        style={StyleSheet.absoluteFillObject}
      />

      <View style={[styles.header, { paddingTop: insets.top + SPACING.s }]}>
          <TouchableOpacity onPress={() => router.back()} style={{ marginRight: SPACING.m }}>
              <Ionicons name="chevron-back" size={24} color="#FFF" />
          </TouchableOpacity>
          <View>
              <Text style={styles.headerTitle}>Super Admin</Text>
              <Text style={styles.headerSub}>Main Developer Control</Text>
          </View>
          <View style={{ flex: 1 }} />
          <View style={styles.adminBadge}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                <Text style={styles.adminBadgeText}>MASTER</Text>
                <Ionicons name="ellipse" size={8} color={socketConnected ? "#000" : "#555"} />
              </View>
          </View>
          <TouchableOpacity onPress={() => setProfileVisible(true)} style={{ marginLeft: 10 }}>
              <Ionicons name="person-circle" size={36} color="#FFF" />
          </TouchableOpacity>
      </View>
      
      <ProfileModal visible={profileVisible} onClose={() => setProfileVisible(false)} />

      <ScrollView contentContainerStyle={{ paddingBottom: 100 }}>
        
        {/* MANAGEMENT CONSOLE */}
        <View style={styles.section}>
            <View style={styles.rowBetween}>
                <Text style={styles.sectionTitle}>Management Console</Text>
                <TouchableOpacity onPress={() => setModalVisible(true)} style={styles.addBtn}>
                    <Text style={styles.addBtnText}>+ Add Entity</Text>
                </TouchableOpacity>
            </View>
            
            <View style={styles.entityList}>
                {entities.map(e => (
                    <View key={e.id} style={styles.entityItem}>
                        <View style={styles.entityIcon}>
                            <Ionicons 
                                name={e.type === 'Manager' ? 'people' : e.type === 'Driver' ? 'bus' : 'person'} 
                                size={20} 
                                color="#FFF" 
                            />
                        </View>
                        <View style={{ flex: 1 }}>
                            <Text style={styles.entityName}>{e.name}</Text>
                            <Text style={styles.entityType}>{e.type}</Text>
                        </View>
                        <TouchableOpacity onPress={() => Alert.alert('Delete', 'Delete this entity?', [{text: 'Cancel'}, {text: 'Delete', style: 'destructive', onPress: () => setEntities(prev => prev.filter(p => p.id !== e.id))}])}>
                             <Ionicons name="trash-outline" size={20} color={COLORS.error} />
                        </TouchableOpacity>
                    </View>
                ))}
            </View>
        </View>

        {/* Stats Grid */}
        <View style={styles.statsGrid}>
            {renderStatCard('Active Buses', buses.length, 'Running now')}
            {renderStatCard('On-Time', `${onTimePercentage}%`, 'Performance')}
            {renderStatCard('Delays', delayedBuses.length, 'Alerts', delayedBuses.length > 0 ? 'rgba(239, 68, 68, 0.2)' : 'rgba(255,255,255,0.1)')}
            {renderStatCard('Passenger Load', 'High', 'Peak Hour', 'rgba(56, 239, 125, 0.15)')}
        </View>

        {/* Map Preview */}
        <View style={styles.mapPreviewContainer}>
            <View style={styles.mapHeader}>
                <Text style={styles.sectionTitle}>Live Fleet View</Text>
            </View>
            <View style={styles.mapWrapper}>
                <BusMap 
                    buses={buses} 
                    stops={stops} 
                    routes={routes} 
                    selectedRouteId={null} 
                    onStopPress={() => {}} 
                    onBusPress={() => {}}
                />
            </View>
        </View>

        {/* Bus List */}
        <View style={styles.section}>
            <Text style={styles.sectionTitle}>Fleet Status</Text>
            {buses.map(bus => (
                <View key={bus.id} style={styles.busItem}>
                    <View style={[styles.busIcon, { backgroundColor: bus.routeColor }]}>
                        <Ionicons name="bus-outline" size={20} color="#FFF" />
                    </View>
                    <View style={{ flex: 1 }}>
                        <Text style={styles.busName}>{bus.routeName} (Bus {bus.id})</Text>
                        <Text style={styles.busSub}>Heading to {stops.find(s=>s.id === bus.nextStopId)?.name}</Text>
                    </View>
                    <View style={[
                        styles.statusPill, 
                        { backgroundColor: bus.status === 'Delayed' ? COLORS.error : COLORS.success }
                    ]}>
                        <Text style={styles.statusTextPill}>{bus.status}</Text>
                    </View>
                </View>
            ))}
        </View>
        
      </ScrollView>

      <AdminUserModal 
        visible={modalVisible} 
        onClose={() => setModalVisible(false)}
        onSave={handleCreated}
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
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: SPACING.m,
      paddingBottom: SPACING.m,
      backgroundColor: 'rgba(255, 255, 255, 0.05)', // Glass header
      borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.1)',
      zIndex: 10,
  },
  headerTitle: {
      fontSize: 20,
      fontWeight: 'bold',
      color: COLORS.text,
  },
  headerSub: {
      fontSize: 14,
      color: COLORS.textSecondary,
  },
  adminBadge: {
      backgroundColor: COLORS.primary,
      paddingHorizontal: 8,
      paddingVertical: 4,
      borderRadius: 4,
  },
  adminBadgeText: {
      color: '#000',
      fontWeight: 'bold',
      fontSize: 10,
  },
  section: {
      paddingHorizontal: SPACING.m,
      marginBottom: SPACING.m,
      marginTop: SPACING.m,
  },
  rowBetween: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      marginBottom: SPACING.s,
  },
  sectionTitle: {
      fontSize: 18,
      fontWeight: 'bold',
      color: COLORS.text,
  },
  addBtn: {
      backgroundColor: COLORS.primary,
      paddingHorizontal: 12,
      paddingVertical: 6,
      borderRadius: 12,
  },
  addBtnText: {
      color: '#000',
      fontWeight: 'bold',
      fontSize: 12,
  },
  entityList: {
      gap: 10,
  },
  entityItem: {
      backgroundColor: 'rgba(255,255,255,0.05)',
      borderRadius: 12,
      padding: SPACING.m,
      flexDirection: 'row',
      alignItems: 'center',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
  },
  entityIcon: {
      width: 36,
      height: 36,
      borderRadius: 18,
      backgroundColor: 'rgba(255,255,255,0.1)',
      justifyContent: 'center',
      alignItems: 'center',
      marginRight: SPACING.m,
  },
  entityName: {
      color: '#fff',
      fontWeight: 'bold',
  },
  entityType: {
      color: 'rgba(255,255,255,0.5)',
      fontSize: 12,
  },
  mapPreviewContainer: {
      margin: SPACING.m,
      height: 200,
      borderRadius: 16,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.2)',
      backgroundColor: 'rgba(0,0,0,0.3)',
  },
  mapHeader: {
      padding: SPACING.s,
      backgroundColor: 'rgba(0,0,0,0.5)',
      zIndex: 1,
  },
  mapWrapper: {
      flex: 1,
  },
  statsGrid: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      paddingHorizontal: SPACING.m,
      justifyContent: 'space-between',
  },
  statCard: {
      width: '48%',
      padding: SPACING.m,
      borderRadius: 16,
      marginBottom: SPACING.m,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
  },
  statValue: {
      fontSize: 24,
      fontWeight: 'bold',
      color: COLORS.text,
  },
  statTitle: {
      fontSize: 14,
      color: COLORS.textLight,
      marginTop: 4,
  },
  statSub: {
      fontSize: 12,
      color: COLORS.primary,
      marginTop: 2,
      fontWeight: '600',
  },
  busItem: {
      flexDirection: 'row',
      alignItems: 'center',
      padding: SPACING.m,
      backgroundColor: 'rgba(255, 255, 255, 0.05)',
      borderRadius: 12,
      marginBottom: SPACING.s,
      borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.1)',
  },
  busIcon: {
      width: 40,
      height: 40,
      borderRadius: 20,
      justifyContent: 'center',
      alignItems: 'center',
      marginRight: SPACING.m,
  },
  busName: {
      fontWeight: 'bold',
      color: COLORS.text,
  },
  busSub: {
      fontSize: 12,
      color: COLORS.textSecondary,
  },
  statusPill: {
      paddingHorizontal: 8,
      paddingVertical: 4,
      borderRadius: 8,
  },
  statusTextPill: {
      color: 'white',
      fontSize: 10,
      fontWeight: 'bold',
  },
  alertCard: {
      margin: SPACING.m,
      padding: SPACING.m,
      backgroundColor: 'rgba(255, 193, 7, 0.1)',
      borderRadius: 12,
      borderWidth: 1,
      borderColor: 'rgba(255, 193, 7, 0.3)',
  },
  alertTitle: {
      fontWeight: 'bold',
      color: COLORS.warning,
      marginBottom: SPACING.s,
  },
  alertText: {
      color: COLORS.textSecondary,
      marginBottom: 4,
  }
});
