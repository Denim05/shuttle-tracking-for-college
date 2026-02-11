import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, FlatList, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';

import { API_URL } from '../../hooks/useAppStore';

const ENDPOINT = `${API_URL}/api/drivers`; 

export default function DriverManager() {
  const [drivers, setDrivers] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);

  // Form State
  const [name, setName] = useState('');
  const [driverId, setDriverId] = useState('');
  const [contactNumber, setContactNumber] = useState('');

  const fetchDrivers = React.useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(ENDPOINT);
      const data = await response.json();
      setDrivers(data);
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Failed to fetch drivers. Is backend running?');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchDrivers();
  }, [fetchDrivers]);

  const handleAddDriver = async () => {
    if (!name || !driverId) {
        Alert.alert('Missing Fields', 'Name and Driver ID are required');
        return;
    }

    try {
        const response = await fetch(ENDPOINT, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, driverId, contactNumber })
        });
        
        if (response.ok) {
            Alert.alert('Success', 'Driver added successfully');
            setName('');
            setDriverId('');
            setContactNumber('');
            setShowAddForm(false);
            fetchDrivers();
        } else {
            Alert.alert('Error', 'Failed to add driver');
        }
    } catch (error) {
        console.warn(error);
        Alert.alert('Error', 'Network error');
    }
  };

  const handleDeleteDriver = async (id: string) => {
      try {
          await fetch(`${ENDPOINT}/${id}`, { method: 'DELETE' });
          fetchDrivers();
      } catch (error) {
          console.warn(error);
          Alert.alert('Error', 'Failed to delete driver');
      }
  };

  const renderItem = ({ item }: any) => (
    <View style={styles.itemCard}>
      <View style={styles.itemInfo}>
        <Text style={styles.itemName}>{item.name}</Text>
        <Text style={styles.itemSub}>ID: {item.driverId}</Text>
        {item.contactNumber && <Text style={styles.itemDetail}>Contact: {item.contactNumber}</Text>}
      </View>
      <TouchableOpacity onPress={() => handleDeleteDriver(item._id)} style={styles.deleteBtn}>
          <Ionicons name="trash-outline" size={20} color="#ff6b6b" />
      </TouchableOpacity>
    </View>
  );

  return (
    <View style={styles.container}>
      <LinearGradient colors={['#0f2027', '#203a43', '#2c5364']} style={styles.background} />
      
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Driver Database</Text>
        <TouchableOpacity onPress={() => setShowAddForm(!showAddForm)} style={styles.addBtn}>
            <Ionicons name={showAddForm ? "close" : "add"} size={24} color="#fff" />
        </TouchableOpacity>
      </View>

      {showAddForm && (
          <View style={styles.formContainer}>
              <TextInput style={styles.input} placeholder="Driver Name" placeholderTextColor="#aaa" value={name} onChangeText={setName} />
              <TextInput style={styles.input} placeholder="License/ID" placeholderTextColor="#aaa" value={driverId} onChangeText={setDriverId} />
              <TextInput style={styles.input} placeholder="Contact Number" placeholderTextColor="#aaa" value={contactNumber} onChangeText={setContactNumber} />
              <TouchableOpacity style={styles.submitBtn} onPress={handleAddDriver}>
                  <Text style={styles.submitBtnText}>Save Driver</Text>
              </TouchableOpacity>
          </View>
      )}

      {loading ? (
        <ActivityIndicator size="large" color="#38ef7d" style={{ marginTop: 20 }} />
      ) : (
        <FlatList
          data={drivers}
          renderItem={renderItem}
          keyExtractor={(item, index) => item._id || item.driverId || index.toString()}
          contentContainerStyle={styles.listContent}
          ListEmptyComponent={<Text style={styles.emptyText}>No drivers found.</Text>}
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
  addBtn: { padding: 10, backgroundColor: '#38ef7d', borderRadius: 20 },
  formContainer: { padding: 20, backgroundColor: 'rgba(255,255,255,0.1)', margin: 10, borderRadius: 10 },
  input: {
      backgroundColor: 'rgba(0,0,0,0.3)', color: '#fff', padding: 12, borderRadius: 8, marginBottom: 10,
      borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)'
  },
  submitBtn: { backgroundColor: '#e67e22', padding: 15, borderRadius: 8, alignItems: 'center' },
  submitBtnText: { color: '#fff', fontWeight: 'bold' },
  listContent: { padding: 15 },
  itemCard: {
      backgroundColor: 'rgba(255,255,255,0.05)', padding: 15, borderRadius: 10, marginBottom: 10,
      flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
      borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)'
  },
  itemInfo: { flex: 1 },
  itemName: { fontSize: 18, fontWeight: 'bold', color: '#fff' },
  itemSub: { fontSize: 14, color: 'rgba(255,255,255,0.6)' },
  itemDetail: { fontSize: 12, color: 'rgba(255,255,255,0.4)', marginTop: 4 },
  deleteBtn: { padding: 10 },
  emptyText: { textAlign: 'center', color: 'rgba(255,255,255,0.5)', marginTop: 20 }
});
