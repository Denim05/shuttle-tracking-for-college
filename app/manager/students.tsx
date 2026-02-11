import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, FlatList, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';

import { API_URL } from '../../hooks/useAppStore';

const ENDPOINT = `${API_URL}/api/students`; 

export default function StudentManager() {
  const [students, setStudents] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);

  // Form State
  const [name, setName] = useState('');
  const [studentId, setStudentId] = useState('');
  const [pickupPoint, setPickupPoint] = useState('');

  const fetchStudents = React.useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(ENDPOINT);
      const data = await response.json();
      setStudents(data);
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Failed to fetch students. Is backend running?');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchStudents();
  }, [fetchStudents]);

  const handleAddStudent = async () => {
    if (!name || !studentId) {
        Alert.alert('Missing Fields', 'Name and Student ID are required');
        return;
    }

    try {
        const response = await fetch(ENDPOINT, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, studentId, pickupPoint })
        });
        
        if (response.ok) {
            Alert.alert('Success', 'Student added successfully');
            setName('');
            setStudentId('');
            setPickupPoint('');
            setShowAddForm(false);
            fetchStudents();
        } else {
            Alert.alert('Error', 'Failed to add student');
        }
    } catch (error) {
        console.warn(error);
        Alert.alert('Error', 'Network error');
    }
  };

  const handleDeleteStudent = async (id: string) => {
      try {
          await fetch(`${ENDPOINT}/${id}`, { method: 'DELETE' });
          fetchStudents();
      } catch (error) {
          console.warn(error);
          Alert.alert('Error', 'Failed to delete student');
      }
  };

  const renderItem = ({ item }: any) => (
    <View style={styles.itemCard}>
      <View style={styles.itemInfo}>
        <Text style={styles.itemName}>{item.name}</Text>
        <Text style={styles.itemSub}>{item.studentId}</Text>
        {item.pickupPoint && <Text style={styles.itemDetail}>Pickup: {item.pickupPoint}</Text>}
      </View>
      <TouchableOpacity onPress={() => handleDeleteStudent(item._id)} style={styles.deleteBtn}>
          <Ionicons name="trash-outline" size={20} color="#ff6b6b" />
      </TouchableOpacity>
    </View>
  );

  return (
    <View style={styles.container}>
      <LinearGradient colors={['#0f2027', '#203a43', '#2c5364']} style={styles.background} />
      
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Student Database</Text>
        <TouchableOpacity onPress={() => setShowAddForm(!showAddForm)} style={styles.addBtn}>
            <Ionicons name={showAddForm ? "close" : "add"} size={24} color="#fff" />
        </TouchableOpacity>
      </View>

      {showAddForm && (
          <View style={styles.formContainer}>
              <TextInput style={styles.input} placeholder="Full Name" placeholderTextColor="#aaa" value={name} onChangeText={setName} />
              <TextInput style={styles.input} placeholder="Student ID" placeholderTextColor="#aaa" value={studentId} onChangeText={setStudentId} />
              <TextInput style={styles.input} placeholder="Pickup Point" placeholderTextColor="#aaa" value={pickupPoint} onChangeText={setPickupPoint} />
              <TouchableOpacity style={styles.submitBtn} onPress={handleAddStudent}>
                  <Text style={styles.submitBtnText}>Save Student</Text>
              </TouchableOpacity>
          </View>
      )}

      {loading ? (
        <ActivityIndicator size="large" color="#38ef7d" style={{ marginTop: 20 }} />
      ) : (
        <FlatList
          data={students}
          renderItem={renderItem}
          keyExtractor={(item, index) => item._id || item.studentId || index.toString()}
          contentContainerStyle={styles.listContent}
          ListEmptyComponent={<Text style={styles.emptyText}>No students found.</Text>}
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
  submitBtn: { backgroundColor: '#3498db', padding: 15, borderRadius: 8, alignItems: 'center' },
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
