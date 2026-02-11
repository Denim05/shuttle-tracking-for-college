import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, FlatList, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import { API_URL } from '../../hooks/useAppStore';

const ENDPOINT = `${API_URL}/api/buses`;

export default function BusManager() {
  const [buses, setBuses] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  // API_URL is now imported from store
 
  const fetchBuses = React.useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(ENDPOINT);
      const data = await response.json();
      setBuses(data);
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Failed to fetch buses. Is backend running?');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchBuses();
  }, [fetchBuses]);

  const updateBusStatus = async (id: string, currentStatus: string) => {
      // Toggle logic or cycle logic
      let newStatus = 'Offline';
      if (currentStatus === 'Offline') newStatus = 'On-time';
      else if (currentStatus === 'On-time') newStatus = 'Delayed';
      else if (currentStatus === 'Delayed') newStatus = 'Offline';

      try {
          const response = await fetch(`${ENDPOINT}/${id}/status`, {
              method: 'PUT',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ status: newStatus })
          });
          
          if (response.ok) {
              fetchBuses(); // Refresh
          } else {
              Alert.alert('Error', 'Failed to update bus status');
          }
      } catch (error) {
          console.warn(error);
          Alert.alert('Error', 'Network error');
      }
  };

  const getStatusColor = (status: string) => {
      switch(status) {
          case 'On-time': return '#4ADE80';
          case 'Delayed': return '#FACC15';
          case 'Offline': return '#9CA3AF';
          default: return '#fff';
      }
  };

  const renderItem = ({ item }: any) => (
    <View style={styles.itemCard}>
      <View style={styles.itemIcon}>
          <Ionicons name="bus" size={24} color={item.routeColor || '#fff'} />
      </View>
      <View style={styles.itemInfo}>
        <Text style={styles.itemName}>{item.routeName || 'Unnamed Route'}</Text>
        <Text style={styles.itemSub}>Route ID: {item.routeId}</Text>
        <View style={[styles.statusBadge, { borderColor: getStatusColor(item.status) }]}>
            <Text style={[styles.statusText, { color: getStatusColor(item.status) }]}>{item.status}</Text>
        </View>
      </View>
      <TouchableOpacity 
        onPress={() => updateBusStatus(item._id, item.status)} 
        style={styles.actionBtn}
      >
          <Text style={styles.actionBtnText}>Change Status</Text>
      </TouchableOpacity>
    </View>
  );

  return (
    <View style={styles.container}>
      <LinearGradient colors={['#0f2027', '#203a43', '#2c5364']} style={styles.background} />
      
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Bus Fleet Status</Text>
        <TouchableOpacity onPress={fetchBuses} style={styles.refreshBtn}>
            <Ionicons name="refresh" size={20} color="#fff" />
        </TouchableOpacity>
      </View>

      {loading ? (
        <ActivityIndicator size="large" color="#38ef7d" style={{ marginTop: 20 }} />
      ) : (
        <FlatList
          data={buses}
          renderItem={renderItem}
          keyExtractor={(item, index) => item._id || item.routeId || index.toString()}
          contentContainerStyle={styles.listContent}
          ListEmptyComponent={<Text style={styles.emptyText}>No buses found in database.</Text>}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  background: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0 },
  header: {
      flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
      padding: 20, paddingTop: 50, backgroundColor: 'rgba(0,0,0,0.3)',
  },
  headerTitle: { fontSize: 22, fontWeight: 'bold', color: '#fff' },
  refreshBtn: { padding: 10, backgroundColor: 'rgba(255,255,255,0.1)', borderRadius: 20 },
  listContent: { padding: 15 },
  itemCard: {
      backgroundColor: 'rgba(255,255,255,0.05)', padding: 15, borderRadius: 10, marginBottom: 10,
      flexDirection: 'row', alignItems: 'center',
      borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)'
  },
  itemIcon: {
      width: 50, height: 50, borderRadius: 25, backgroundColor: 'rgba(255,255,255,0.1)',
      justifyContent: 'center', alignItems: 'center', marginRight: 15
  },
  itemInfo: { flex: 1 },
  itemName: { fontSize: 18, fontWeight: 'bold', color: '#fff' },
  itemSub: { fontSize: 14, color: 'rgba(255,255,255,0.6)', marginBottom: 5 },
  statusBadge: {
      borderWidth: 1, paddingHorizontal: 8, paddingVertical: 2, borderRadius: 10, alignSelf: 'flex-start'
  },
  statusText: { fontSize: 12, fontWeight: 'bold' },
  actionBtn: {
      backgroundColor: 'rgba(255,255,255,0.1)', paddingHorizontal: 15, paddingVertical: 10, borderRadius: 8
  },
  actionBtnText: { color: '#fff', fontSize: 12 },
  emptyText: { textAlign: 'center', color: 'rgba(255,255,255,0.5)', marginTop: 20 }
});
