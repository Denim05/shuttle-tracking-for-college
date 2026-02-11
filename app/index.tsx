import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import React, { useEffect } from 'react';
import {
  ActivityIndicator,
  Alert,
  Dimensions,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View
} from 'react-native';
import Animated, { FadeInDown, FadeInUp, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { useAppStore } from '../hooks/useAppStore';

const { width, height } = Dimensions.get('window');

// Custom Input Component with Icon
const InputField = ({ icon, placeholder, value, onChangeText, secureTextEntry = false }: any) => {
  const focused = useSharedValue(0);

  const animatedStyle = useAnimatedStyle(() => {
    return {
      borderColor: withTiming(focused.value ? '#3498db' : 'rgba(255,255,255,0.3)'),
      borderWidth: 1,
      backgroundColor: withTiming(focused.value ? 'rgba(255,255,255,0.15)' : 'rgba(255,255,255,0.08)'),
    };
  });

  return (
    <Animated.View style={[styles.inputContainer, animatedStyle]}>
      <Ionicons name={icon} size={20} color="rgba(255,255,255,0.7)" style={{ marginRight: 10 }} />
      <TextInput
        style={styles.input}
        placeholder={placeholder}
        placeholderTextColor="rgba(255,255,255,0.5)"
        value={value}
        onChangeText={onChangeText}
        secureTextEntry={secureTextEntry}
        onFocus={() => (focused.value = 1)}
        onBlur={() => (focused.value = 0)}
        autoCapitalize="none"
      />
    </Animated.View>
  );
};

export default function LoginScreen() {
  const router = useRouter();
  const login = useAppStore((state) => state.login);
  const fetchInitialData = useAppStore((state) => state.fetchInitialData);
  
  const [name, setName] = React.useState('');
  const [password, setPassword] = React.useState('');
  const [loading, setLoading] = React.useState(false);
  const [role, setRole] = React.useState<'user' | 'driver' | 'admin' | 'manager'>('user');

  useEffect(() => {
    fetchInitialData();
  }, [fetchInitialData]);

  const handleLogin = async () => {
    if (!name.trim() || !password.trim()) {
      Alert.alert('Missing Fields', 'Please enter both Username and Password');
      return;
    }
    setLoading(true);
    const result = await login(name, password, role);
    setLoading(false);

    if (result.success) {
      if (role === 'user') {
        router.push('/user' as any);
      } else if (role === 'driver') {
        router.push('/driver' as any);
      } else if (role === 'manager') {
        // manager folder exists
        router.push('/manager' as any);
      } else {
        router.push('/admin/dashboard' as any);
      }
    } else {
      Alert.alert('Login Failed', result.error || 'Invalid credentials');
    }
  };

  return (
    <View style={styles.mainContainer}>
      <LinearGradient
        colors={['#0f2027', '#203a43', '#2c5364']} // Deep glossy space/teal theme
        style={styles.background}
      />
      
      <KeyboardAvoidingView 
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'} 
        style={{ flex: 1 }}
      >
        <ScrollView contentContainerStyle={styles.scrollContainer} showsVerticalScrollIndicator={false}>
          
          {/* Header Section */}
          <Animated.View entering={FadeInDown.delay(200).springify()}>
            <View style={styles.logoContainer}>
              <View style={styles.iconCircle}>
                <Ionicons name="bus" size={40} color="#fff" />
              </View>
              <Text style={styles.title}>Sistec Chalo</Text>
              <Text style={styles.subtitle}>Smart Transport for Smart Campus</Text>
            </View>
          </Animated.View>

          {/* Login Form Card */}
          <Animated.View entering={FadeInUp.delay(400).springify()} style={styles.card}>
            <Text style={styles.cardHeader}>CUSTOMER LOGIN</Text>
            <View style={styles.divider} />

            <View style={styles.formContent}>
              <InputField 
                icon="person-outline" 
                placeholder="Username" 
                value={name} 
                onChangeText={setName} 
              />
              
              <InputField 
                icon="lock-closed-outline" 
                placeholder="Password" 
                value={password} 
                onChangeText={setPassword}
                secureTextEntry={true}
              />

              <View style={styles.optionsRow}>
                <TouchableOpacity style={styles.optionItem}>
                  <Ionicons name="checkbox-outline" size={18} color="rgba(255,255,255,0.6)" />
                  <Text style={styles.optionText}>Remember me</Text>
                </TouchableOpacity>
                <TouchableOpacity>
                  <Text style={[styles.optionText, { color: '#4ADE80' }]}>Forgot ID?</Text>
                </TouchableOpacity>
              </View>

              <TouchableOpacity 
                activeOpacity={0.8}
                onPress={handleLogin}
              >
                <LinearGradient
                  colors={['#11998e', '#38ef7d']}
                  start={{ x: 0, y: 0 }}
                  end={{ x: 1, y: 0 }}
                  style={styles.loginButton}
                >
                  {loading ? (
                    <ActivityIndicator color="#fff" />
                  ) : (
                    <Text style={styles.loginButtonText}>LOGIN</Text>
                  )}
                </LinearGradient>
              </TouchableOpacity>
            </View>

            {/* Role Selection (To keep functionality) */}
            <View style={styles.roleSelector}>
               <Text style={styles.roleLabel}>Select Role:</Text>
                 <View style={styles.roleButtons}>
                 {(['user', 'driver', 'admin', 'manager'] as const).map((r) => (
                   <TouchableOpacity 
                      key={r} 
                      onPress={() => setRole(r)}
                      style={[
                        styles.roleBtn, 
                        role === r && styles.roleBtnActive
                      ]}
                   >
                     <Text style={[
                       styles.roleBtnText,
                       role === r && styles.roleBtnTextActive
                     ]}>
                       {r.charAt(0).toUpperCase() + r.slice(1)}
                     </Text>
                   </TouchableOpacity>
                 ))}
               </View>
            </View>

          </Animated.View>
          
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  mainContainer: {
    flex: 1,
  },
  background: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
  },
  scrollContainer: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 20,
    paddingTop: 60,
  },
  logoContainer: {
    alignItems: 'center',
    marginBottom: 30,
  },
  iconCircle: {
    width: 70, 
    height: 70, 
    borderRadius: 35, 
    backgroundColor: 'rgba(255,255,255,0.1)', 
    alignItems: 'center', 
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
    marginBottom: 15,
  },
  title: {
    fontSize: 34,
    fontWeight: 'bold',
    color: '#fff',
    letterSpacing: 1,
  },
  subtitle: {
    fontSize: 16,
    color: 'rgba(255,255,255,0.7)',
    marginTop: 5,
  },
  card: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)', // Glassmorphism
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
    padding: 0,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 10,
  },
  cardHeader: {
    textAlign: 'center',
    color: '#38ef7d', // Greenish teal
    fontSize: 18,
    fontWeight: 'bold',
    letterSpacing: 2,
    paddingVertical: 20,
    backgroundColor: 'rgba(0,0,0,0.2)',
  },
  divider: {
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.1)',
  },
  formContent: {
    padding: 25,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 15,
    paddingVertical: 12,
    borderRadius: 30,
    marginBottom: 20,
  },
  input: {
    flex: 1,
    color: '#fff',
    fontSize: 16,
  },
  optionsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 25,
  },
  optionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  optionText: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 13,
  },
  loginButton: {
    borderRadius: 30,
    paddingVertical: 15,
    alignItems: 'center',
    shadowColor: '#38ef7d',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.5,
    shadowRadius: 10,
    elevation: 5,
  },
  loginButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
    letterSpacing: 1,
  },
  roleSelector: {
    padding: 20,
    backgroundColor: 'rgba(0,0,0,0.1)',
    alignItems: 'center',
  },
  roleLabel: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 12,
    marginBottom: 10,
    textTransform: 'uppercase',
  },
  roleButtons: {
    flexDirection: 'row',
    gap: 10,
  },
  roleBtn: {
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.2)',
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  roleBtnActive: {
    borderColor: '#38ef7d',
    backgroundColor: 'rgba(56, 239, 125, 0.1)',
  },
  roleBtnText: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 12,
  },
  roleBtnTextActive: {
    color: '#38ef7d',
    fontWeight: 'bold',
  },
});
