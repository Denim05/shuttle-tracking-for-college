
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import React from 'react';
import { Modal, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { COLORS, SHADOWS } from '../constants/theme';
import { useAppStore } from '../hooks/useAppStore';

interface ProfileModalProps {
  visible: boolean;
  onClose: () => void;
}

export default function ProfileModal({ visible, onClose }: ProfileModalProps) {
  const router = useRouter();
  const { username, userRole, logout, isLowDataMode, setLowDataMode } = useAppStore();

  const handleLogout = async () => {
    await logout();
    onClose();
    router.replace('/');
  };

  return (
    <Modal
      visible={visible}
      transparent={true}
      animationType="fade"
      onRequestClose={onClose}
    >
      <TouchableOpacity 
        style={styles.overlay} 
        activeOpacity={1} 
        onPress={onClose}
      >
        <TouchableOpacity activeOpacity={1} style={styles.modalContent}>
            <LinearGradient
                colors={['#1e3c72', '#2a5298']}
                style={styles.header}
            >
                <View style={styles.avatar}>
                    <Ionicons name="person" size={40} color="#FFF" />
                </View>
                <Text style={styles.username}>{username || 'User'}</Text>
                <View style={styles.roleBadge}>
                    <Text style={styles.roleText}>{userRole?.toUpperCase()}</Text>
                </View>
                
                <TouchableOpacity style={styles.closeBtn} onPress={onClose}>
                    <Ionicons name="close" size={20} color="#FFF" />
                </TouchableOpacity>
            </LinearGradient>
            
            <View style={styles.body}>
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>Settings</Text>
                    
                    <TouchableOpacity 
                        style={styles.row} 
                        onPress={() => setLowDataMode(!isLowDataMode)}
                    >
                        <View style={styles.rowLeft}>
                            <View style={[styles.iconBox, { backgroundColor: isLowDataMode ? COLORS.warning : COLORS.primary }]}>
                                <Ionicons name={isLowDataMode ? "cellular" : "wifi"} size={18} color="#FFF" />
                            </View>
                            <Text style={styles.rowText}>Low Data Mode</Text>
                        </View>
                        <View style={[styles.toggle, isLowDataMode && styles.toggleActive]}>
                            <View style={[styles.toggleHandle, isLowDataMode && styles.toggleHandleActive]} />
                        </View>
                    </TouchableOpacity>
                </View>

                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>Account</Text>
                    
                    <TouchableOpacity style={styles.row} onPress={() => {}}>
                         <View style={styles.rowLeft}>
                            <View style={[styles.iconBox, { backgroundColor: '#9b59b6' }]}>
                                <Ionicons name="settings-outline" size={18} color="#FFF" />
                            </View>
                            <Text style={styles.rowText}>Preferences</Text>
                         </View>
                         <Ionicons name="chevron-forward" size={20} color={COLORS.textSecondary} />
                    </TouchableOpacity>
                </View>

                <TouchableOpacity style={styles.logoutBtn} onPress={handleLogout}>
                    <Text style={styles.logoutText}>Log Out</Text>
                    <Ionicons name="log-out-outline" size={20} color="#FFF" />
                </TouchableOpacity>
            </View>
        </TouchableOpacity>
      </TouchableOpacity>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  modalContent: {
    width: '100%',
    maxWidth: 340,
    backgroundColor: '#0f2027', // Using dark theme background
    borderRadius: 20,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    ...SHADOWS.medium
  },
  header: {
    alignItems: 'center',
    paddingVertical: 30,
    paddingHorizontal: 20,
  },
  closeBtn: {
      position: 'absolute',
      right: 15,
      top: 15,
      padding: 5,
      backgroundColor: 'rgba(0,0,0,0.2)',
      borderRadius: 15,
  },
  avatar: {
      width: 80,
      height: 80,
      borderRadius: 40,
      backgroundColor: 'rgba(255,255,255,0.2)',
      justifyContent: 'center',
      alignItems: 'center',
      marginBottom: 10,
      borderWidth: 2,
      borderColor: 'rgba(255,255,255,0.3)',
  },
  username: {
      fontSize: 22,
      fontWeight: 'bold',
      color: '#FFF',
      marginBottom: 5,
  },
  roleBadge: {
      paddingHorizontal: 12,
      paddingVertical: 4,
      backgroundColor: 'rgba(255,255,255,0.2)',
      borderRadius: 12,
  },
  roleText: {
      fontSize: 12,
      color: '#FFF',
      fontWeight: 'bold',
      letterSpacing: 1,
  },
  body: {
      padding: 20,
      backgroundColor: '#0f2027', 
  },
  section: {
      marginBottom: 25,
  },
  sectionTitle: {
      fontSize: 12,
      color: COLORS.textSecondary,
      fontWeight: 'bold',
      marginBottom: 10,
      textTransform: 'uppercase',
      letterSpacing: 1,
  },
  row: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      paddingVertical: 12,
      borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  rowLeft: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
  },
  iconBox: {
      width: 32,
      height: 32,
      borderRadius: 10,
      justifyContent: 'center',
      alignItems: 'center',
  },
  rowText: {
      color: COLORS.text,
      fontSize: 16,
  },
  toggle: {
      width: 44,
      height: 24,
      borderRadius: 12,
      backgroundColor: 'rgba(255,255,255,0.1)',
      padding: 2,
  },
  toggleActive: {
      backgroundColor: COLORS.success,
  },
  toggleHandle: {
      width: 20,
      height: 20,
      borderRadius: 10,
      backgroundColor: '#FFF',
  },
  toggleHandleActive: {
      transform: [{ translateX: 20 }],
  },
  logoutBtn: {
      flexDirection: 'row',
      justifyContent: 'center',
      alignItems: 'center',
      gap: 10,
      backgroundColor: COLORS.error,
      paddingVertical: 15,
      borderRadius: 12,
      marginTop: 10,
  },
  logoutText: {
      color: '#FFF',
      fontWeight: 'bold',
      fontSize: 16,
  }
});
