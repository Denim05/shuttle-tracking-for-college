import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import React, { useEffect, useState, useMemo } from 'react';
import { ActivityIndicator, Alert, FlatList, StyleSheet, Text, TextInput, TouchableOpacity, View, ScrollView } from 'react-native';
import * as DocumentPicker from 'expo-document-picker';
import * as FileSystem from 'expo-file-system';

import { API_URL, useAppStore } from '../../hooks/useAppStore';
import { COLORS } from '../../constants/theme';

const STUDENTS_ENDPOINT = `${API_URL}/api/students`; 
const REGISTRATIONS_ENDPOINT = `${API_URL}/api/manager/registrations`;

type ActiveTab = 'database' | 'approvals' | 'import';

export default function StudentManager() {
  const authToken = useAppStore((state) => state.authToken);
  
  const [activeTab, setActiveTab] = useState<ActiveTab>('database');
  const [loading, setLoading] = useState(false);
  
  // Database Tab State
  const [students, setStudents] = useState<any[]>([]);
  const [showAddForm, setShowAddForm] = useState(false);
  const [name, setName] = useState('');
  const [studentId, setStudentId] = useState('');
  const [pickupPoint, setPickupPoint] = useState('');

  // Approvals Tab State
  const [pendingSubmissions, setPendingSubmissions] = useState<any[]>([]);

  // Import Tab State
  const [csvInput, setCsvInput] = useState('');
  const [parsedData, setParsedData] = useState<any[]>([]);
  const [parseErrors, setParseErrors] = useState<string[]>([]);
  const [fileName, setFileName] = useState('');

  const authHeaders = useMemo(() => ({
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${authToken}`
  }), [authToken]);

  // Fetch approved students (Database)
  const fetchStudents = React.useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(STUDENTS_ENDPOINT);
      const data = await response.json();
      setStudents(data);
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Failed to fetch student database.');
    } finally {
      setLoading(false);
    }
  }, []);

  // Fetch pending approvals
  const fetchPendingSubmissions = React.useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(`${REGISTRATIONS_ENDPOINT}?status=pending`, {
        headers: authHeaders
      });
      const data = await response.json();
      setPendingSubmissions(Array.isArray(data) ? data : []);
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Failed to fetch pending approvals.');
    } finally {
      setLoading(false);
    }
  }, [authHeaders]);

  useEffect(() => {
    if (activeTab === 'database') {
      fetchStudents();
    } else if (activeTab === 'approvals') {
      fetchPendingSubmissions();
    }
  }, [activeTab, fetchStudents, fetchPendingSubmissions]);

  // Add individual student manually
  const handleAddStudent = async () => {
    if (!name || !studentId) {
        Alert.alert('Missing Fields', 'Name and Student ID are required');
        return;
    }

    try {
        const response = await fetch(STUDENTS_ENDPOINT, {
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

  // Delete student manually
  const handleDeleteStudent = async (id: string) => {
      try {
          await fetch(`${STUDENTS_ENDPOINT}/${id}`, { method: 'DELETE' });
          fetchStudents();
      } catch (error) {
          console.warn(error);
          Alert.alert('Error', 'Failed to delete student');
      }
  };

  // Approve a pending registration submission
  const handleApproveSubmission = async (id: string, studentName: string) => {
    try {
      setLoading(true);
      const response = await fetch(`${REGISTRATIONS_ENDPOINT}/${id}/approve`, {
        method: 'PUT',
        headers: authHeaders
      });
      
      const data = await response.json();
      if (response.ok) {
        Alert.alert(
          'Registration Approved',
          `Account created for ${studentName} successfully!\n\n` +
          `Username: "${data.username}"\n` +
          `Password: "${data.password}"\n\n` +
          `Please copy and share these credentials with the student.`,
          [{ text: 'OK', onPress: () => fetchPendingSubmissions() }]
        );
      } else {
        Alert.alert('Approval Failed', data.error || 'Failed to approve student');
      }
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Network error during approval.');
    } finally {
      setLoading(false);
    }
  };

  // Reject a pending registration submission
  const handleRejectSubmission = async (id: string) => {
    try {
      setLoading(true);
      const response = await fetch(`${REGISTRATIONS_ENDPOINT}/${id}/reject`, {
        method: 'PUT',
        headers: authHeaders,
        body: JSON.stringify({ note: 'Rejected by manager' })
      });
      if (response.ok) {
        Alert.alert('Success', 'Registration rejected.', [
          { text: 'OK', onPress: () => fetchPendingSubmissions() }
        ]);
      } else {
        const data = await response.json();
        Alert.alert('Error', data.error || 'Failed to reject registration');
      }
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Network error during rejection.');
    } finally {
      setLoading(false);
    }
  };

  // Pick Document File (CSV)
  const handlePickDocument = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ['text/comma-separated-values', 'text/csv'],
        copyToCacheDirectory: true,
      });

      if (!result.canceled && result.assets && result.assets.length > 0) {
        const file = result.assets[0];
        setFileName(file.name);
        const text = await FileSystem.readAsStringAsync(file.uri);
        setCsvInput(text);
        parseCSV(text);
      }
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Failed to pick or read CSV file.');
    }
  };

  // CSV Text Parsing Engine
  const parseCSV = (text: string) => {
    if (!text.trim()) {
      setParsedData([]);
      setParseErrors([]);
      return;
    }

    const lines = text.split(/\r?\n/);
    if (lines.length < 2) {
      setParseErrors(['CSV must contain a header row and at least one data row.']);
      return;
    }

    // Helper to clean column strings
    const cleanCell = (str: string) => {
      if (!str) return '';
      return str.replace(/^["']|["']$/g, '').trim();
    };

    // Header Mapping
    const rawHeaders = lines[0].split(',').map(h => h.trim().toLowerCase());
    const mappedIndexes = {
      name: rawHeaders.findIndex(h => h.includes('name')),
      studentId: rawHeaders.findIndex(h => h.includes('id') || h.includes('enroll') || h.includes('roll')),
      phone: rawHeaders.findIndex(h => h.includes('phone') || h.includes('mobile') || h.includes('mob') || h.includes('contact')),
      email: rawHeaders.findIndex(h => h.includes('email') || h.includes('mail')),
      routeName: rawHeaders.findIndex(h => h.includes('route')),
      pickupStop: rawHeaders.findIndex(h => h.includes('stop') || h.includes('pickup') || h.includes('point'))
    };

    // Validation
    const errors: string[] = [];
    if (mappedIndexes.name === -1) errors.push('Missing "Name" header.');
    if (mappedIndexes.studentId === -1) errors.push('Missing "Student ID" or "Enrollment Number" header.');
    if (mappedIndexes.phone === -1) errors.push('Missing "Phone" or "Mobile" header.');
    if (mappedIndexes.pickupStop === -1) errors.push('Missing "Stop" or "Pickup Point" header.');

    if (errors.length > 0) {
      setParseErrors(errors);
      setParsedData([]);
      return;
    }

    const parsedRows: any[] = [];
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue; // Skip empty rows

      // Handle simple quotes inside CSV split
      const row = line.match(/(".*?"|[^",\s]+)(?=\s*,|\s*$)/g) || line.split(',');
      
      const student = {
        name: cleanCell(row[mappedIndexes.name]),
        studentId: cleanCell(row[mappedIndexes.studentId]),
        phone: cleanCell(row[mappedIndexes.phone]),
        email: mappedIndexes.email !== -1 ? cleanCell(row[mappedIndexes.email]) : '',
        routeName: mappedIndexes.routeName !== -1 ? cleanCell(row[mappedIndexes.routeName]) : '',
        pickupStop: cleanCell(row[mappedIndexes.pickupStop])
      };

      // Inline validation for row
      if (!student.name || !student.studentId || !student.phone || !student.pickupStop) {
        errors.push(`Row ${i + 1}: Missing required cells.`);
      }

      parsedRows.push(student);
    }

    setParseErrors(errors);
    setParsedData(parsedRows);
  };

  // Submit bulk imports to backend
  const handleBulkUpload = async () => {
    if (parsedData.length === 0) {
      Alert.alert('No Data', 'Please pick a valid CSV or paste data first.');
      return;
    }

    if (parseErrors.length > 0) {
      Alert.alert('Parsing Errors Exist', 'Please fix formatting warnings before importing.');
      return;
    }

    try {
      setLoading(true);
      const response = await fetch(`${REGISTRATIONS_ENDPOINT}/bulk`, {
        method: 'POST',
        headers: authHeaders,
        body: JSON.stringify({ submissions: parsedData })
      });

      const data = await response.json();
      if (response.ok) {
        const errorSummary = data.errors && data.errors.length > 0 
          ? `\n\nFailed records (${data.errors.length}):\n${data.errors.slice(0, 5).join('\n')}` 
          : '';
        Alert.alert(
          'Import Complete',
          `Imported ${data.importedCount} new student registrations successfully!${errorSummary}`,
          [{ text: 'OK', onPress: () => {
            setCsvInput('');
            setParsedData([]);
            setFileName('');
            setActiveTab('approvals');
          }}]
        );
      } else {
        Alert.alert('Upload Failed', data.error || 'Failed to submit registrations.');
      }
    } catch (error) {
      console.warn(error);
      Alert.alert('Error', 'Network error during bulk import.');
    } finally {
      setLoading(false);
    }
  };

  // Render a student card in approved database roster
  const renderRosterItem = ({ item }: any) => (
    <View style={styles.itemCard}>
      <View style={styles.itemInfo}>
        <Text style={styles.itemName}>{item.name}</Text>
        <Text style={styles.itemSub}>{item.studentId}</Text>
        {item.pickupPoint && <Text style={styles.itemDetail}>Pickup Stop: {item.pickupPoint}</Text>}
      </View>
      <TouchableOpacity onPress={() => handleDeleteStudent(item._id)} style={styles.deleteBtn}>
          <Ionicons name="trash-outline" size={20} color="#ff6b6b" />
      </TouchableOpacity>
    </View>
  );

  // Render a pending registration request card
  const renderApprovalItem = ({ item }: any) => (
    <View style={styles.itemCard}>
      <View style={styles.itemInfo}>
        <View style={styles.badgeRow}>
          <Text style={styles.itemName}>{item.name}</Text>
          <View style={styles.pendingBadge}>
            <Text style={styles.pendingText}>PENDING</Text>
          </View>
        </View>
        <Text style={styles.itemSub}>ID: {item.studentId} | Mob: {item.phone}</Text>
        <Text style={styles.itemDetail}>Route: {item.routeName || 'Unassigned'}</Text>
        <Text style={styles.itemDetail}>Pickup: {item.pickupStop}</Text>
      </View>
      <View style={styles.actionColumn}>
        <TouchableOpacity 
          onPress={() => handleApproveSubmission(item._id, item.name)} 
          style={[styles.actionBtn, styles.approveBtn]}
        >
          <Ionicons name="checkmark-circle-outline" size={20} color="#fff" />
          <Text style={styles.actionBtnText}>Approve</Text>
        </TouchableOpacity>
        <TouchableOpacity 
          onPress={() => handleRejectSubmission(item._id)} 
          style={[styles.actionBtn, styles.rejectBtn]}
        >
          <Ionicons name="close-circle-outline" size={20} color="#fff" />
          <Text style={styles.actionBtnText}>Reject</Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  return (
    <View style={styles.container}>
      <LinearGradient colors={['#0f2027', '#203a43', '#2c5364']} style={styles.background} />
      
      {/* Redesigned Tab Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Manager Console</Text>
        
        {activeTab === 'database' && (
          <TouchableOpacity onPress={() => setShowAddForm(!showAddForm)} style={styles.addBtn}>
              <Ionicons name={showAddForm ? "close" : "add"} size={22} color="#000" />
          </TouchableOpacity>
        )}
      </View>

      {/* Tabs */}
      <View style={styles.tabBar}>
        <TouchableOpacity 
          style={[styles.tab, activeTab === 'database' && styles.activeTab]}
          onPress={() => setActiveTab('database')}
        >
          <Ionicons name="people" size={18} color={activeTab === 'database' ? COLORS.primary : '#ccc'} />
          <Text style={[styles.tabText, activeTab === 'database' && styles.activeTabText]}>Roster</Text>
        </TouchableOpacity>
        <TouchableOpacity 
          style={[styles.tab, activeTab === 'approvals' && styles.activeTab]}
          onPress={() => setActiveTab('approvals')}
        >
          <Ionicons name="checkmark-done-circle" size={18} color={activeTab === 'approvals' ? COLORS.primary : '#ccc'} />
          <Text style={[styles.tabText, activeTab === 'approvals' && styles.activeTabText]}>Approvals</Text>
          {pendingSubmissions.length > 0 && (
            <View style={styles.alertCount}>
              <Text style={styles.alertCountText}>{pendingSubmissions.length}</Text>
            </View>
          )}
        </TouchableOpacity>
        <TouchableOpacity 
          style={[styles.tab, activeTab === 'import' && styles.activeTab]}
          onPress={() => setActiveTab('import')}
        >
          <Ionicons name="cloud-upload" size={18} color={activeTab === 'import' ? COLORS.primary : '#ccc'} />
          <Text style={[styles.tabText, activeTab === 'import' && styles.activeTabText]}>Import</Text>
        </TouchableOpacity>
      </View>

      {loading && <ActivityIndicator size="large" color="#38ef7d" style={{ marginVertical: 15 }} />}

      {/* TAB 1: Approved Students */}
      {activeTab === 'database' && (
        <View style={{ flex: 1 }}>
          {showAddForm && (
            <View style={styles.formContainer}>
              <TextInput style={styles.input} placeholder="Full Name" placeholderTextColor="#aaa" value={name} onChangeText={setName} />
              <TextInput style={styles.input} placeholder="Student ID" placeholderTextColor="#aaa" value={studentId} onChangeText={setStudentId} />
              <TextInput style={styles.input} placeholder="Pickup Stop" placeholderTextColor="#aaa" value={pickupPoint} onChangeText={setPickupPoint} />
              <TouchableOpacity style={styles.submitBtn} onPress={handleAddStudent}>
                <Text style={styles.submitBtnText}>Save Student</Text>
              </TouchableOpacity>
            </View>
          )}

          <FlatList
            data={students}
            renderItem={renderRosterItem}
            keyExtractor={(item, index) => item._id || item.studentId || index.toString()}
            contentContainerStyle={styles.listContent}
            ListEmptyComponent={!loading ? <Text style={styles.emptyText}>No students in approved database.</Text> : null}
          />
        </View>
      )}

      {/* TAB 2: Pending Registrations approvals */}
      {activeTab === 'approvals' && (
        <FlatList
          data={pendingSubmissions}
          renderItem={renderApprovalItem}
          keyExtractor={(item, index) => item._id || item.studentId || index.toString()}
          contentContainerStyle={styles.listContent}
          ListEmptyComponent={!loading ? <Text style={styles.emptyText}>No pending registration requests.</Text> : null}
        />
      )}

      {/* TAB 3: CSV Import Pane */}
      {activeTab === 'import' && (
        <ScrollView style={styles.scrollContainer} contentContainerStyle={{ paddingBottom: 60 }}>
          <View style={styles.importCard}>
            <Text style={styles.importTitle}>CSV File Upload</Text>
            <Text style={styles.importDescription}>
              Select a CSV file from your device, or paste the comma-separated data containing Name, Student ID, Phone, Route, and Stop fields below.
            </Text>

            <TouchableOpacity style={styles.pickerButton} onPress={handlePickDocument}>
              <Ionicons name="document-text" size={24} color="#FFF" style={{ marginRight: 8 }} />
              <Text style={styles.pickerButtonText}>
                {fileName ? fileName : 'Choose CSV File'}
              </Text>
            </TouchableOpacity>

            <Text style={styles.orText}>— OR PASTE CSV ROWS BELOW —</Text>

            <TextInput
              style={styles.textArea}
              multiline
              numberOfLines={8}
              placeholder="Name,Student ID,Phone,Email,Route,Stop&#10;John Doe,SGI2026001,9876543210,john@sgi.edu,Gandinagar Route,Gandhi Nagar"
              placeholderTextColor="rgba(255,255,255,0.25)"
              value={csvInput}
              onChangeText={(text) => {
                setCsvInput(text);
                parseCSV(text);
              }}
            />

            {/* Parsing summary or errors */}
            {parseErrors.length > 0 && (
              <View style={styles.errorBox}>
                <Ionicons name="alert-circle" size={20} color="#ff6b6b" style={{ marginRight: 6 }} />
                <View style={{ flex: 1 }}>
                  <Text style={styles.errorBoxTitle}>Warnings & Formatter Errors:</Text>
                  {parseErrors.slice(0, 3).map((err, idx) => (
                    <Text key={idx} style={styles.errorBoxText}>• {err}</Text>
                  ))}
                </View>
              </View>
            )}

            {parsedData.length > 0 && (
              <View style={styles.successBox}>
                <Ionicons name="checkmark-circle" size={20} color="#2ecc71" style={{ marginRight: 6 }} />
                <Text style={styles.successBoxText}>
                  Parsed {parsedData.length} records successfully! Ready to upload.
                </Text>
              </View>
            )}

            <TouchableOpacity 
              style={[styles.importSubmitBtn, (parsedData.length === 0 || parseErrors.length > 0) && styles.disabledBtn]} 
              onPress={handleBulkUpload}
              disabled={parsedData.length === 0 || parseErrors.length > 0}
            >
              <Text style={styles.importSubmitBtnText}>Upload & Process Submissions</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  background: { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0 },
  header: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    paddingHorizontal: 20, paddingTop: 60, paddingBottom: 15,
    backgroundColor: 'rgba(0,0,0,0.2)',
  },
  headerTitle: { fontSize: 22, fontWeight: 'bold', color: '#fff' },
  addBtn: { padding: 8, backgroundColor: COLORS.primary, borderRadius: 20 },
  tabBar: {
    flexDirection: 'row',
    backgroundColor: 'rgba(0,0,0,0.4)',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)',
  },
  tab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    gap: 6,
  },
  activeTab: {
    borderBottomWidth: 3,
    borderBottomColor: COLORS.primary,
  },
  tabText: {
    color: '#aaa',
    fontSize: 13,
    fontWeight: '600',
  },
  activeTabText: {
    color: COLORS.primary,
    fontWeight: 'bold',
  },
  alertCount: {
    backgroundColor: 'red',
    borderRadius: 8,
    paddingHorizontal: 5,
    paddingVertical: 1,
    marginLeft: 4,
  },
  alertCountText: {
    color: 'white',
    fontSize: 10,
    fontWeight: 'bold',
  },
  formContainer: { padding: 20, backgroundColor: 'rgba(255,255,255,0.08)', margin: 10, borderRadius: 12 },
  input: {
    backgroundColor: 'rgba(0,0,0,0.3)', color: '#fff', padding: 12, borderRadius: 8, marginBottom: 10,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)'
  },
  submitBtn: { backgroundColor: '#3498db', padding: 12, borderRadius: 8, alignItems: 'center' },
  submitBtnText: { color: '#fff', fontWeight: 'bold' },
  listContent: { padding: 15 },
  itemCard: {
    backgroundColor: 'rgba(255,255,255,0.04)', padding: 15, borderRadius: 16, marginBottom: 10,
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)'
  },
  itemInfo: { flex: 1, paddingRight: 10 },
  badgeRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8 },
  itemName: { fontSize: 18, fontWeight: 'bold', color: '#fff' },
  pendingBadge: {
    backgroundColor: 'rgba(241, 196, 15, 0.15)',
    borderWidth: 1,
    borderColor: '#f1c40f',
    borderRadius: 4,
    paddingHorizontal: 6,
    paddingVertical: 1,
  },
  pendingText: {
    color: '#f1c40f',
    fontSize: 8,
    fontWeight: 'bold',
  },
  itemSub: { fontSize: 13, color: 'rgba(255,255,255,0.5)', marginTop: 2 },
  itemDetail: { fontSize: 12, color: 'rgba(255,255,255,0.35)', marginTop: 3 },
  deleteBtn: { padding: 10 },
  actionColumn: {
    flexDirection: 'column',
    gap: 8,
    justifyContent: 'center',
  },
  actionBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 8,
    gap: 4,
  },
  approveBtn: {
    backgroundColor: '#2ecc71',
  },
  rejectBtn: {
    backgroundColor: '#e74c3c',
  },
  actionBtnText: {
    color: 'white',
    fontSize: 12,
    fontWeight: 'bold',
  },
  emptyText: { textAlign: 'center', color: 'rgba(255,255,255,0.4)', marginTop: 40, fontSize: 14 },
  
  // Import tab styles
  scrollContainer: { flex: 1, padding: 15 },
  importCard: {
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 16,
    padding: 20,
  },
  importTitle: { fontSize: 18, fontWeight: 'bold', color: '#fff', marginBottom: 6 },
  importDescription: { fontSize: 13, color: 'rgba(255,255,255,0.5)', lineHeight: 1.5, marginBottom: 20 },
  pickerButton: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderWidth: 1.5,
    borderStyle: 'dashed',
    borderColor: 'rgba(255,255,255,0.25)',
    borderRadius: 12,
    padding: 16,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 15,
  },
  pickerButtonText: { color: '#FFF', fontWeight: 'bold', fontSize: 14 },
  orText: { color: 'rgba(255,255,255,0.25)', fontSize: 10, fontWeight: 'bold', alignSelf: 'center', marginVertical: 10 },
  textArea: {
    backgroundColor: 'rgba(0,0,0,0.4)',
    color: '#FFF',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12,
    padding: 12,
    fontSize: 13,
    fontFamily: 'monospace',
    height: 120,
    textAlignVertical: 'top',
    marginBottom: 15,
  },
  errorBox: {
    flexDirection: 'row',
    backgroundColor: 'rgba(231, 76, 60, 0.08)',
    borderWidth: 1,
    borderColor: 'rgba(231, 76, 60, 0.2)',
    borderRadius: 12,
    padding: 12,
    marginBottom: 15,
  },
  errorBoxTitle: { color: '#ff6b6b', fontWeight: 'bold', fontSize: 12, marginBottom: 4 },
  errorBoxText: { color: '#ff8a8a', fontSize: 11 },
  successBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(46, 204, 113, 0.08)',
    borderWidth: 1,
    borderColor: 'rgba(46, 204, 113, 0.2)',
    borderRadius: 12,
    padding: 12,
    marginBottom: 15,
  },
  successBoxText: { color: '#2ecc71', fontSize: 12, fontWeight: '600' },
  importSubmitBtn: {
    backgroundColor: COLORS.primary,
    padding: 15,
    borderRadius: 12,
    alignItems: 'center',
  },
  disabledBtn: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    opacity: 0.5,
  },
  importSubmitBtnText: { color: '#000', fontWeight: 'bold', fontSize: 15 },
});
