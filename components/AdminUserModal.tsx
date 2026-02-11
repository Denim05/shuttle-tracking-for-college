import React, { useState } from 'react';
import { Modal, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { COLORS, SHADOWS, SPACING } from '../constants/theme';

interface AdminUserModalProps {
    visible: boolean;
    onClose: () => void;
    onSave: (type: 'user' | 'driver' | 'manager', data: any) => void;
}

export default function AdminUserModal({ visible, onClose, onSave }: AdminUserModalProps) {
    const [type, setType] = useState<'user' | 'driver' | 'manager'>('user');
    const [formData, setFormData] = useState<any>({});

    const handleSave = () => {
        onSave(type, formData);
        setFormData({});
        onClose();
    };

    const updateField = (key: string, value: string) => {
        setFormData((prev: any) => ({ ...prev, [key]: value }));
    };

    return (
        <Modal visible={visible} transparent animationType="slide">
            <View style={styles.modalOverlay}>
                <View style={styles.modalContent}>
                    <Text style={styles.title}>Create New Entity</Text>
                    
                    {/* Type Selector */}
                    <View style={styles.typeSelector}>
                        {(['user', 'driver', 'manager'] as const).map(t => (
                            <TouchableOpacity 
                                key={t} 
                                style={[styles.typeBtn, type === t && styles.typeBtnActive]}
                                onPress={() => setType(t)}
                            >
                                <Text style={[styles.typeText, type === t && styles.typeTextActive]}>
                                    {t.charAt(0).toUpperCase() + t.slice(1)}
                                </Text>
                            </TouchableOpacity>
                        ))}
                    </View>

                    {/* Dynamic Fields */}
                    <TextInput 
                        placeholder="Username" 
                        placeholderTextColor="#aaa"
                        style={styles.input}
                        onChangeText={t => updateField('username', t)}
                    />
                    <TextInput 
                        placeholder="Password" 
                        placeholderTextColor="#aaa"
                        secureTextEntry
                        style={styles.input}
                        onChangeText={t => updateField('password', t)}
                    />

                    {type === 'driver' && (
                        <>
                            <TextInput 
                                placeholder="Full Name" 
                                placeholderTextColor="#aaa"
                                style={styles.input}
                                onChangeText={t => updateField('name', t)}
                            />
                            <TextInput 
                                placeholder="Driver ID (License)" 
                                placeholderTextColor="#aaa"
                                style={styles.input}
                                onChangeText={t => updateField('driverId', t)}
                            />
                        </>
                    )}

                    {type === 'manager' && (
                        <>
                             <TextInput 
                                placeholder="Employee ID" 
                                placeholderTextColor="#aaa"
                                style={styles.input}
                                onChangeText={t => updateField('employeeId', t)}
                            />
                            <TextInput 
                                placeholder="Department" 
                                placeholderTextColor="#aaa"
                                style={styles.input}
                                onChangeText={t => updateField('department', t)}
                            />
                        </>
                    )}

                    <View style={styles.actions}>
                        <TouchableOpacity onPress={onClose} style={[styles.btn, styles.cancelBtn]}>
                            <Text style={styles.btnText}>Cancel</Text>
                        </TouchableOpacity>
                        <TouchableOpacity onPress={handleSave} style={[styles.btn, styles.saveBtn]}>
                            <Text style={[styles.btnText, { color: '#000' }]}>Create {type}</Text>
                        </TouchableOpacity>
                    </View>
                </View>
            </View>
        </Modal>
    );
}

const styles = StyleSheet.create({
    modalOverlay: {
        flex: 1,
        backgroundColor: 'rgba(0,0,0,0.6)',
        justifyContent: 'center',
        padding: SPACING.m,
    },
    modalContent: {
        backgroundColor: '#1a1a1a',
        borderRadius: 20,
        padding: SPACING.l,
        borderWidth: 1,
        borderColor: 'rgba(255,255,255,0.1)',
        ...SHADOWS.medium,
    },
    title: {
        fontSize: 20,
        fontWeight: 'bold',
        color: '#fff',
        marginBottom: SPACING.m,
        textAlign: 'center',
    },
    typeSelector: {
        flexDirection: 'row',
        marginBottom: SPACING.m,
        backgroundColor: 'rgba(255,255,255,0.05)',
        borderRadius: 10,
        padding: 4,
    },
    typeBtn: {
        flex: 1,
        paddingVertical: 8,
        alignItems: 'center',
        borderRadius: 8,
    },
    typeBtnActive: {
        backgroundColor: COLORS.primary,
    },
    typeText: {
        color: '#aaa',
        fontSize: 12,
        fontWeight: '600',
    },
    typeTextActive: {
        color: '#000',
    },
    input: {
        backgroundColor: 'rgba(255,255,255,0.1)',
        borderRadius: 10,
        padding: 12,
        color: '#fff',
        marginBottom: 12,
        borderWidth: 1,
        borderColor: 'rgba(255,255,255,0.1)',
    },
    actions: {
        flexDirection: 'row',
        gap: 12,
        marginTop: SPACING.s,
    },
    btn: {
        flex: 1,
        padding: 14,
        borderRadius: 10,
        alignItems: 'center',
    },
    cancelBtn: {
        backgroundColor: 'rgba(255,255,255,0.1)',
    },
    saveBtn: {
        backgroundColor: COLORS.primary,
    },
    btnText: {
        color: '#fff',
        fontWeight: 'bold',
    },
});
