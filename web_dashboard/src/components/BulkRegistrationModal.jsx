import React, { useState, useRef } from 'react';
import * as XLSX from 'xlsx';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  UploadCloud, FileSpreadsheet, CheckCircle2, AlertCircle, 
  Trash2, Download, ArrowRight, Check, X, RefreshCw, 
  Sparkles, FileText, Filter, AlertTriangle, ShieldCheck, ChevronDown
} from 'lucide-react';
import { registrationAPI } from '../services/api';

const TARGET_FIELDS = [
  { key: 'name', label: 'Student Name *', required: true, aliases: ['name', 'student name', 'fullname', 'full name', 'student', 'name of student', 'candidate name'] },
  { key: 'studentId', label: 'Roll No / Student ID *', required: true, aliases: ['roll no', 'roll number', 'rollno', 'enrollment no', 'enrollment', 'scholar no', 'student id', 'studentid', 'id', 'user id'] },
  { key: 'phone', label: 'Phone Number *', required: true, aliases: ['phone', 'mobile', 'contact', 'contact no', 'mobile no', 'phone number', 'student phone', 'cell'] },
  { key: 'pickupStop', label: 'Pickup Stop / Point *', required: true, aliases: ['pickup stop', 'pickup point', 'stop', 'bus stop', 'boarding point', 'pickup', 'stop name', 'location'] },
  { key: 'routeName', label: 'Assigned Route', required: false, aliases: ['route', 'route name', 'bus route', 'assigned route', 'bus no', 'bus line'] },
  { key: 'courseName', label: 'Course / Branch', required: false, aliases: ['course', 'branch', 'dept', 'department', 'program', 'class', 'sem', 'semester', 'degree'] },
  { key: 'email', label: 'Email Address', required: false, aliases: ['email', 'email id', 'mail', 'student email', 'email address'] },
  { key: 'fatherName', label: "Father's Name", required: false, aliases: ['father name', "father's name", 'parent name', 'guardian name', 'father'] },
  { key: 'fatherPhone', label: 'Father Phone', required: false, aliases: ['father phone', 'parent phone', 'emergency contact', 'guardian phone', 'parent contact'] },
  { key: 'gender', label: 'Gender', required: false, aliases: ['gender', 'sex'] },
];

export default function BulkRegistrationModal({ isOpen, onClose, onSuccess, availableRoutes = [] }) {
  const [step, setStep] = useState(1); // 1: Upload, 2: Column Mapping & Validation, 3: Success Report
  const [dragActive, setDragActive] = useState(false);
  const [fileInfo, setFileInfo] = useState(null);
  const [rawHeaders, setRawHeaders] = useState([]);
  const [rawRows, setRawRows] = useState([]);
  const [columnMapping, setColumnMapping] = useState({});
  const [parsedStudents, setParsedStudents] = useState([]);
  const [filterPreview, setFilterPreview] = useState('all'); // 'all', 'valid', 'invalid'
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [uploadResult, setUploadResult] = useState(null);
  const fileInputRef = useRef(null);

  if (!isOpen) return null;

  // Reset state
  const handleReset = () => {
    setStep(1);
    setFileInfo(null);
    setRawHeaders([]);
    setRawRows([]);
    setColumnMapping({});
    setParsedStudents([]);
    setUploadResult(null);
  };

  // Process uploaded File (Excel / CSV / JSON)
  const processFile = (file) => {
    if (!file) return;

    const fileName = file.name.toLowerCase();
    const isExcel = fileName.endsWith('.xlsx') || fileName.endsWith('.xls');
    const isCsv = fileName.endsWith('.csv') || fileName.endsWith('.tsv') || fileName.endsWith('.txt');
    const isJson = fileName.endsWith('.json');

    if (!isExcel && !isCsv && !isJson) {
      alert('Please upload an Excel (.xlsx, .xls), CSV (.csv), or JSON file.');
      return;
    }

    const reader = new FileReader();

    if (isJson) {
      reader.onload = (e) => {
        try {
          const json = JSON.parse(e.target.result);
          const dataArray = Array.isArray(json) ? json : [json];
          if (dataArray.length === 0) throw new Error('Empty JSON array');

          const headers = Object.keys(dataArray[0]);
          setRawHeaders(headers);
          setRawRows(dataArray);
          setFileInfo({ name: file.name, size: (file.size / 1024).toFixed(1) + ' KB', rowCount: dataArray.length });
          autoMapColumns(headers, dataArray);
          setStep(2);
        } catch (err) {
          alert('Failed to parse JSON file. Ensure it contains a valid array of objects.');
        }
      };
      reader.readAsText(file);
    } else {
      reader.onload = (e) => {
        try {
          const data = new Uint8Array(e.target.result);
          const workbook = XLSX.read(data, { type: 'array' });
          const firstSheetName = workbook.SheetNames[0];
          const worksheet = workbook.Sheets[firstSheetName];

          // Parse as array of objects
          const jsonData = XLSX.utils.sheet_to_json(worksheet, { defval: '' });

          if (!jsonData || jsonData.length === 0) {
            alert('The uploaded sheet has no data rows.');
            return;
          }

          // Extract headers
          const headers = Object.keys(jsonData[0]);
          setRawHeaders(headers);
          setRawRows(jsonData);
          setFileInfo({
            name: file.name,
            size: (file.size / 1024).toFixed(1) + ' KB',
            rowCount: jsonData.length,
            sheetName: firstSheetName
          });

          autoMapColumns(headers, jsonData);
          setStep(2);
        } catch (err) {
          console.error('File parsing error:', err);
          alert('Could not read this file. Please make sure it is a valid Excel or CSV spreadsheet.');
        }
      };
      reader.readAsArrayBuffer(file);
    }
  };

  // Smart Auto-Mapping of Columns based on header names & aliases
  const autoMapColumns = (headers, rows) => {
    const initialMapping = {};

    TARGET_FIELDS.forEach(field => {
      // Find matching header by aliases
      const matchedHeader = headers.find(h => {
        const cleanHeader = h.toString().toLowerCase().trim();
        return field.aliases.some(alias => cleanHeader === alias || cleanHeader.includes(alias));
      });

      if (matchedHeader) {
        initialMapping[field.key] = matchedHeader;
      } else {
        initialMapping[field.key] = '';
      }
    });

    setColumnMapping(initialMapping);
    generateValidatedStudents(initialMapping, rows);
  };

  // Build validated list of students from current mapping
  const generateValidatedStudents = (mapping, rows = rawRows) => {
    const students = rows.map((row, index) => {
      const student = {
        _rowIndex: index + 1,
        name: row[mapping.name] ? String(row[mapping.name]).trim() : '',
        studentId: row[mapping.studentId] ? String(row[mapping.studentId]).trim() : '',
        phone: row[mapping.phone] ? String(row[mapping.phone]).trim().replace(/[^0-9+]/g, '') : '',
        pickupStop: row[mapping.pickupStop] ? String(row[mapping.pickupStop]).trim() : '',
        routeName: row[mapping.routeName] ? String(row[mapping.routeName]).trim() : '',
        courseName: row[mapping.courseName] ? String(row[mapping.courseName]).trim() : '',
        email: row[mapping.email] ? String(row[mapping.email]).trim() : '',
        fatherName: row[mapping.fatherName] ? String(row[mapping.fatherName]).trim() : '',
        fatherPhone: row[mapping.fatherPhone] ? String(row[mapping.fatherPhone]).trim() : '',
        gender: row[mapping.gender] ? String(row[mapping.gender]).trim() : '',
      };

      const errors = [];
      if (!student.name) errors.push('Missing Name');
      if (!student.studentId) errors.push('Missing Roll No');
      if (!student.phone || student.phone.length < 7) errors.push('Invalid/Missing Phone');
      if (!student.pickupStop) errors.push('Missing Pickup Stop');

      return {
        ...student,
        isValid: errors.length === 0,
        errors
      };
    });

    setParsedStudents(students);
  };

  // Handle Mapping Dropdown Change
  const handleMappingChange = (fieldKey, selectedHeader) => {
    const updated = { ...columnMapping, [fieldKey]: selectedHeader };
    setColumnMapping(updated);
    generateValidatedStudents(updated);
  };

  // Download Pre-Configured Clean Template
  const downloadSampleTemplate = (format = 'xlsx') => {
    const sampleData = [
      {
        'Student Name': 'Aman Sharma',
        'Roll No': '0192CS221001',
        'Phone Number': '9826012345',
        'Pickup Stop': 'Indrapuri B-Sector',
        'Assigned Route': 'Indrapuri Express',
        'Course / Branch': 'B.Tech CSE',
        'Email Address': 'aman.sharma@example.com',
        "Father's Name": 'Rajesh Sharma',
        'Father Phone': '9826054321',
        'Gender': 'Male'
      },
      {
        'Student Name': 'Pooja Verma',
        'Roll No': '0192EC221015',
        'Phone Number': '9876543210',
        'Pickup Stop': 'MP Nagar Zone 1',
        'Assigned Route': 'MP Nagar Shuttle',
        'Course / Branch': 'B.Tech ECE',
        'Email Address': 'pooja.verma@example.com',
        "Father's Name": 'Suresh Verma',
        'Father Phone': '9876501234',
        'Gender': 'Female'
      },
      {
        'Student Name': 'Rohan Patel',
        'Roll No': '0192ME221033',
        'Phone Number': '9123456789',
        'Pickup Stop': 'Bairagarh Bus Stand',
        'Assigned Route': 'Bairagarh Direct',
        'Course / Branch': 'B.Tech ME',
        'Email Address': 'rohan.patel@example.com',
        "Father's Name": 'Mukesh Patel',
        'Father Phone': '9123456780',
        'Gender': 'Male'
      }
    ];

    const worksheet = XLSX.utils.json_to_sheet(sampleData);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Student Registrations');

    if (format === 'csv') {
      XLSX.writeFile(workbook, 'SISTecChalo_Student_Import_Template.csv', { bookType: 'csv' });
    } else {
      XLSX.writeFile(workbook, 'SISTecChalo_Student_Import_Template.xlsx', { bookType: 'xlsx' });
    }
  };

  // Execute Bulk Upload to Backend
  const handleFinalImport = async () => {
    const validStudents = parsedStudents.filter(s => s.isValid);

    if (validStudents.length === 0) {
      alert('No valid student rows to import. Please check required column mappings.');
      return;
    }

    setIsSubmitting(true);
    try {
      const payload = validStudents.map(({ _rowIndex, isValid, errors, ...data }) => data);
      const res = await registrationAPI.bulkUpload(payload);

      setUploadResult({
        success: true,
        importedCount: res.data?.importedCount || validStudents.length,
        errors: res.data?.errors || [],
        totalAttempted: validStudents.length
      });

      setStep(3);
      if (onSuccess) onSuccess();
    } catch (err) {
      console.error('Bulk upload failed:', err);
      alert(err.response?.data?.error || 'Failed to complete bulk upload. Please check network connection.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const validCount = parsedStudents.filter(s => s.isValid).length;
  const invalidCount = parsedStudents.filter(s => !s.isValid).length;

  const displayedStudents = parsedStudents.filter(s => {
    if (filterPreview === 'valid') return s.isValid;
    if (filterPreview === 'invalid') return !s.isValid;
    return true;
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <motion.div 
        initial={{ opacity: 0, scale: 0.96 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.96 }}
        className="w-full max-w-4xl bg-[#0B1120] border border-gray-800 rounded-3xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]"
      >
        {/* Modal Header */}
        <div className="p-6 border-b border-gray-800/80 flex items-center justify-between bg-gray-900/40">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-2xl bg-indigo-500/10 border border-indigo-500/30 flex items-center justify-center text-indigo-400">
              <FileSpreadsheet className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-white font-display">Bulk Student Registration Studio</h3>
              <p className="text-xs text-gray-400">Import hundreds of students seamlessly via Excel, CSV, or JSON</p>
            </div>
          </div>

          <button 
            onClick={() => { handleReset(); onClose(); }}
            className="p-2 rounded-xl text-gray-400 hover:text-white hover:bg-gray-800/60 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Modal Body */}
        <div className="p-6 overflow-y-auto flex-1 space-y-6">

          {/* STEP 1: Upload Dropzone */}
          {step === 1 && (
            <div className="space-y-6">
              
              {/* Drag & Drop Zone */}
              <div 
                onDragOver={(e) => { e.preventDefault(); setDragActive(true); }}
                onDragLeave={() => setDragActive(false)}
                onDrop={(e) => {
                  e.preventDefault();
                  setDragActive(false);
                  if (e.dataTransfer.files && e.dataTransfer.files[0]) {
                    processFile(e.dataTransfer.files[0]);
                  }
                }}
                onClick={() => fileInputRef.current?.click()}
                className={`border-2 border-dashed rounded-3xl p-10 flex flex-col items-center justify-center text-center cursor-pointer transition ${
                  dragActive 
                    ? 'border-indigo-500 bg-indigo-500/10 scale-[0.99]' 
                    : 'border-gray-700/80 hover:border-indigo-500/60 bg-gray-900/30 hover:bg-gray-900/50'
                }`}
              >
                <input 
                  type="file" 
                  ref={fileInputRef} 
                  onChange={(e) => e.target.files?.[0] && processFile(e.target.files[0])}
                  accept=".xlsx, .xls, .csv, .tsv, .json, .txt" 
                  className="hidden" 
                />

                <div className="w-16 h-16 rounded-3xl bg-indigo-600/15 border border-indigo-500/30 flex items-center justify-center text-indigo-400 mb-4 glow-primary">
                  <UploadCloud className="w-8 h-8" />
                </div>

                <h4 className="text-base font-semibold text-white">
                  Drop your Excel, CSV, or JSON spreadsheet here
                </h4>
                <p className="text-xs text-gray-400 mt-1 max-w-md">
                  Click to browse from your device. Supports <span className="text-emerald-400 font-mono">.xlsx</span>, <span className="text-cyan-400 font-mono">.xls</span>, <span className="text-indigo-400 font-mono">.csv</span>, and <span className="text-amber-400 font-mono">.json</span>.
                </p>

                <div className="flex items-center space-x-2 mt-6">
                  <span className="px-3 py-1 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-[10px] font-semibold rounded-full">
                    Excel (.xlsx / .xls)
                  </span>
                  <span className="px-3 py-1 bg-cyan-500/10 border border-cyan-500/20 text-cyan-400 text-[10px] font-semibold rounded-full">
                    CSV / TSV
                  </span>
                  <span className="px-3 py-1 bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 text-[10px] font-semibold rounded-full">
                    JSON Array
                  </span>
                </div>
              </div>

              {/* Template Download Card */}
              <div className="glass-card p-5 rounded-2xl flex flex-col sm:flex-row items-center justify-between gap-4">
                <div className="flex items-center space-x-3">
                  <div className="w-10 h-10 rounded-xl bg-cyan-500/10 border border-cyan-500/30 flex items-center justify-center text-cyan-400">
                    <FileText className="w-5 h-5" />
                  </div>
                  <div>
                    <h5 className="text-sm font-semibold text-white">Need the official template?</h5>
                    <p className="text-xs text-gray-400">Download our pre-structured spreadsheet with student roll numbers, pickup stops, and routes.</p>
                  </div>
                </div>

                <div className="flex items-center space-x-2 w-full sm:w-auto">
                  <button 
                    onClick={() => downloadSampleTemplate('xlsx')}
                    className="flex-1 sm:flex-none px-4 py-2 rounded-xl bg-emerald-600/20 hover:bg-emerald-600/30 border border-emerald-500/40 text-emerald-300 text-xs font-semibold flex items-center justify-center space-x-2 transition"
                  >
                    <Download className="w-3.5 h-3.5" />
                    <span>Download Excel</span>
                  </button>
                  <button 
                    onClick={() => downloadSampleTemplate('csv')}
                    className="flex-1 sm:flex-none px-4 py-2 rounded-xl bg-gray-800 hover:bg-gray-700 border border-gray-700 text-gray-300 text-xs font-semibold flex items-center justify-center space-x-2 transition"
                  >
                    <Download className="w-3.5 h-3.5 text-cyan-400" />
                    <span>CSV Template</span>
                  </button>
                </div>
              </div>

            </div>
          )}

          {/* STEP 2: Smart Column Mapping & Live Preview */}
          {step === 2 && (
            <div className="space-y-6">
              
              {/* File Info Bar */}
              <div className="glass-panel p-4 rounded-2xl flex flex-wrap items-center justify-between gap-3 text-xs border border-gray-800">
                <div className="flex items-center space-x-3">
                  <div className="p-2 bg-indigo-500/10 rounded-xl text-indigo-400">
                    <FileSpreadsheet className="w-4 h-4" />
                  </div>
                  <div>
                    <p className="font-semibold text-white">{fileInfo?.name}</p>
                    <p className="text-[11px] text-gray-400">{fileInfo?.rowCount} total rows parsed • {fileInfo?.size}</p>
                  </div>
                </div>

                <div className="flex items-center space-x-2">
                  <span className="px-3 py-1 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 font-semibold text-[11px] flex items-center space-x-1">
                    <Check className="w-3.5 h-3.5" />
                    <span>{validCount} Valid</span>
                  </span>
                  {invalidCount > 0 && (
                    <span className="px-3 py-1 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-400 font-semibold text-[11px] flex items-center space-x-1">
                      <AlertTriangle className="w-3.5 h-3.5" />
                      <span>{invalidCount} Needs Attention</span>
                    </span>
                  )}
                  <button 
                    onClick={handleReset}
                    className="px-3 py-1 rounded-lg bg-gray-800 hover:bg-gray-700 text-gray-300 text-[11px] font-semibold transition"
                  >
                    Change File
                  </button>
                </div>
              </div>

              {/* Column Mapping Accordion */}
              <div className="glass-panel p-5 rounded-2xl border border-gray-800 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-2">
                    <Sparkles className="w-4 h-4 text-indigo-400" />
                    <h4 className="text-sm font-bold text-white font-display">Auto-Detected Column Mapping</h4>
                  </div>
                  <span className="text-[11px] text-gray-400">Adjust dropdowns if fields don't match automatically</span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 text-xs">
                  {TARGET_FIELDS.map((field) => (
                    <div key={field.key} className="p-3 rounded-xl bg-gray-900/60 border border-gray-800 flex flex-col justify-between space-y-1.5">
                      <div className="flex items-center justify-between">
                        <label className={`font-semibold ${field.required ? 'text-indigo-300' : 'text-gray-300'}`}>
                          {field.label}
                        </label>
                        {columnMapping[field.key] ? (
                          <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                        ) : field.required ? (
                          <AlertCircle className="w-3.5 h-3.5 text-amber-400" />
                        ) : null}
                      </div>

                      <select 
                        value={columnMapping[field.key] || ''}
                        onChange={(e) => handleMappingChange(field.key, e.target.value)}
                        className="glass-input px-2.5 py-1.5 rounded-lg text-xs w-full bg-gray-950/80 border-gray-700 text-gray-200"
                      >
                        <option value="">-- Ignore / Unmapped --</option>
                        {rawHeaders.map((header) => (
                          <option key={header} value={header}>{header}</option>
                        ))}
                      </select>
                    </div>
                  ))}
                </div>
              </div>

              {/* Live Preview Header & Tabs */}
              <div className="flex items-center justify-between pt-2">
                <div className="flex items-center space-x-2 text-xs">
                  <span className="font-semibold text-gray-300">Preview Data ({displayedStudents.length}):</span>
                  <button 
                    onClick={() => setFilterPreview('all')}
                    className={`px-3 py-1 rounded-lg font-medium transition ${filterPreview === 'all' ? 'bg-indigo-600 text-white' : 'bg-gray-800 text-gray-400'}`}
                  >
                    All ({parsedStudents.length})
                  </button>
                  <button 
                    onClick={() => setFilterPreview('valid')}
                    className={`px-3 py-1 rounded-lg font-medium transition ${filterPreview === 'valid' ? 'bg-emerald-600 text-white' : 'bg-gray-800 text-gray-400'}`}
                  >
                    Valid ({validCount})
                  </button>
                  {invalidCount > 0 && (
                    <button 
                      onClick={() => setFilterPreview('invalid')}
                      className={`px-3 py-1 rounded-lg font-medium transition ${filterPreview === 'invalid' ? 'bg-rose-600 text-white' : 'bg-gray-800 text-gray-400'}`}
                    >
                      Invalid ({invalidCount})
                    </button>
                  )}
                </div>
              </div>

              {/* Live Data Preview Table */}
              <div className="glass-panel rounded-2xl overflow-hidden border border-gray-800 max-h-64 overflow-y-auto">
                <table className="w-full text-left text-xs">
                  <thead className="bg-gray-900/90 text-gray-400 uppercase tracking-wider text-[10px] sticky top-0 border-b border-gray-800">
                    <tr>
                      <th className="p-3 w-8 text-center">#</th>
                      <th className="p-3">Status</th>
                      <th className="p-3">Student Name</th>
                      <th className="p-3">Roll No</th>
                      <th className="p-3">Phone</th>
                      <th className="p-3">Pickup Stop</th>
                      <th className="p-3">Route</th>
                      <th className="p-3">Course</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-800/60">
                    {displayedStudents.map((s, idx) => (
                      <tr key={idx} className={s.isValid ? 'hover:bg-gray-800/30' : 'bg-rose-950/20 hover:bg-rose-950/30'}>
                        <td className="p-3 text-center text-gray-500 font-mono">{s._rowIndex}</td>
                        <td className="p-3">
                          {s.isValid ? (
                            <span className="px-2 py-0.5 rounded-md bg-emerald-500/10 text-emerald-400 text-[10px] font-semibold flex items-center space-x-1 w-max">
                              <Check className="w-3 h-3" />
                              <span>Ready</span>
                            </span>
                          ) : (
                            <span className="px-2 py-0.5 rounded-md bg-rose-500/10 text-rose-400 text-[10px] font-semibold flex items-center space-x-1 w-max" title={s.errors.join(', ')}>
                              <AlertTriangle className="w-3 h-3" />
                              <span>{s.errors[0]}</span>
                            </span>
                          )}
                        </td>
                        <td className="p-3 font-semibold text-white">{s.name || '<Empty>'}</td>
                        <td className="p-3 font-mono text-indigo-400">{s.studentId || '<Empty>'}</td>
                        <td className="p-3 text-gray-300 font-mono">{s.phone || '<Empty>'}</td>
                        <td className="p-3 text-cyan-300">{s.pickupStop || '<Empty>'}</td>
                        <td className="p-3 text-gray-400">{s.routeName || 'Auto-Match'}</td>
                        <td className="p-3 text-gray-400">{s.courseName || '-'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

            </div>
          )}

          {/* STEP 3: Success Report */}
          {step === 3 && uploadResult && (
            <div className="text-center py-8 space-y-4">
              <div className="w-16 h-16 rounded-full bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center text-emerald-400 mx-auto glow-emerald">
                <CheckCircle2 className="w-8 h-8" />
              </div>

              <h4 className="text-xl font-bold text-white font-display">Bulk Import Successful!</h4>
              <p className="text-xs text-gray-400 max-w-md mx-auto">
                Successfully registered <strong className="text-emerald-400 font-bold">{uploadResult.importedCount} students</strong> into the SISTecChalo transport database.
              </p>

              {uploadResult.errors && uploadResult.errors.length > 0 && (
                <div className="glass-panel p-4 rounded-2xl border border-amber-500/30 text-left max-h-40 overflow-y-auto max-w-lg mx-auto text-xs space-y-1">
                  <p className="font-semibold text-amber-400 flex items-center space-x-1 mb-2">
                    <AlertTriangle className="w-3.5 h-3.5" />
                    <span>Notice ({uploadResult.errors.length} skipped duplicates/errors):</span>
                  </p>
                  {uploadResult.errors.map((err, i) => (
                    <p key={i} className="text-gray-400 text-[11px]">• {err}</p>
                  ))}
                </div>
              )}

              <div className="pt-4 flex items-center justify-center space-x-3">
                <button 
                  onClick={() => { handleReset(); onClose(); }}
                  className="px-6 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-lg glow-primary transition"
                >
                  Done & View Registrations
                </button>
              </div>
            </div>
          )}

        </div>

        {/* Modal Footer */}
        {step === 2 && (
          <div className="p-5 border-t border-gray-800/80 bg-gray-900/40 flex items-center justify-between">
            <button 
              onClick={() => setStep(1)}
              className="px-4 py-2 rounded-xl bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs font-semibold transition"
            >
              Back to Upload
            </button>

            <button 
              onClick={handleFinalImport}
              disabled={isSubmitting || validCount === 0}
              className="px-6 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white text-xs font-semibold shadow-lg glow-primary flex items-center space-x-2 transition"
            >
              {isSubmitting ? (
                <>
                  <RefreshCw className="w-4 h-4 animate-spin" />
                  <span>Processing {validCount} Records...</span>
                </>
              ) : (
                <>
                  <CheckCircle2 className="w-4 h-4" />
                  <span>Import {validCount} Students to Database</span>
                </>
              )}
            </button>
          </div>
        )}

      </motion.div>
    </div>
  );
}
