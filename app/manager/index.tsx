import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import React, { useState } from 'react';
import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import ProfileModal from '../../components/ProfileModal';

export default function ManagerDashboard() {
  const router = useRouter();
  const [profileVisible, setProfileVisible] = useState(false);

  const DashboardCard = ({ title, icon, route, color }: any) => (
    <TouchableOpacity 
      style={styles.cardContainer}
      onPress={() => router.push(route as any)}
      activeOpacity={0.8}
    >
      <LinearGradient
        colors={['rgba(255,255,255,0.1)', 'rgba(255,255,255,0.05)']}
        style={styles.card}
      >
        <View style={[styles.iconContainer, { backgroundColor: color }]}>
          <Ionicons name={icon} size={32} color="#fff" />
        </View>
        <Text style={styles.cardTitle}>{title}</Text>
        <Text style={styles.cardSubtitle}>Manage {title}</Text>
        <Ionicons name="arrow-forward" size={20} color="rgba(255,255,255,0.5)" style={styles.arrow} />
      </LinearGradient>
    </TouchableOpacity>
  );

  return (
    <View style={styles.container}>
      <LinearGradient
        colors={['#0f2027', '#203a43', '#2c5364']}
        style={styles.background}
      />
      
      <View style={styles.header}>
        <View>
            <Text style={styles.headerTitle}>Transport Authority</Text>
            <Text style={styles.headerSubtitle}>Manager Dashboard</Text>
        </View>
        <TouchableOpacity onPress={() => setProfileVisible(true)} style={styles.profileBtn}>
            <Ionicons name="person-circle" size={40} color="#FFF" />
        </TouchableOpacity>
      </View>
      
      <ProfileModal visible={profileVisible} onClose={() => setProfileVisible(false)} />

      <ScrollView contentContainerStyle={styles.content}>
        <DashboardCard 
          title="Students" 
          icon="school" 
          route="/manager/students" 
          color="#3498db" 
        />
        <DashboardCard 
          title="Drivers" 
          icon="id-card" 
          route="/manager/drivers" 
          color="#e67e22" 
        />
        <DashboardCard 
          title="Buses" 
          icon="bus" 
          route="/manager/buses" 
          color="#2ecc71" 
        />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  background: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
  },
  header: {
    paddingTop: 60,
    paddingBottom: 20,
    paddingHorizontal: 20,
    backgroundColor: 'rgba(0,0,0,0.2)',
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  profileBtn: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 20,
  },
  headerTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#fff',
    letterSpacing: 1,
  },
  headerSubtitle: {
    fontSize: 14,
    color: 'rgba(255,255,255,0.6)',
    marginTop: 5,
  },
  content: {
    padding: 20,
    gap: 20,
  },
  cardContainer: {
    marginBottom: 15,
  },
  card: {
    padding: 20,
    borderRadius: 15,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    flexDirection: 'row',
    alignItems: 'center',
  },
  iconContainer: {
    width: 60,
    height: 60,
    borderRadius: 30,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 20,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 4.65,
    elevation: 8,
  },
  cardTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#fff',
    flex: 1,
  },
  cardSubtitle: {
    position: 'absolute',
    bottom: 20,
    left: 100, // Approximate position
    fontSize: 12,
    color: 'rgba(255,255,255,0.4)',
  },
  arrow: {
    marginLeft: 10,
  }
});
