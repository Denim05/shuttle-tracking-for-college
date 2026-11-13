/**
 * google_sheets_service.js
 * Automated Google Sheets Sync Service for SISTec Chalo Shuttle System.
 * Generates dedicated Morning & Evening Shift Sheets with 100% Real Timetable & Live GPS Data.
 */

const { google } = require('googleapis');
const path = require('path');
const fs = require('fs');

const SPREADSHEET_ID = process.env.GOOGLE_SPREADSHEET_ID || '16V1Og-UYtzN8gM1x3Bj4wZLjdw5-fyvWFMWucwby8EE';

let authClient = null;

function getAuthClient() {
    if (authClient) return authClient;

    const credsPath = path.resolve(__dirname, '..', 'google_sheets_credentials.json');
    if (fs.existsSync(credsPath)) {
        authClient = new google.auth.GoogleAuth({
            keyFile: credsPath,
            scopes: ['https://www.googleapis.com/auth/spreadsheets']
        });
        return authClient;
    }

    if (process.env.GOOGLE_SHEETS_CREDENTIALS) {
        try {
            const credentials = JSON.parse(process.env.GOOGLE_SHEETS_CREDENTIALS);
            authClient = new google.auth.GoogleAuth({
                credentials,
                scopes: ['https://www.googleapis.com/auth/spreadsheets']
            });
            return authClient;
        } catch (e) {
            console.error('Failed to parse GOOGLE_SHEETS_CREDENTIALS env var:', e.message);
        }
    }

    throw new Error('Google Sheets credentials not found. Please provide backend/google_sheets_credentials.json');
}

/**
 * Ensures required tabs and formatted headers exist in the Google Spreadsheet
 */
async function initializeSpreadsheetTabs(sheets, spreadsheetId = SPREADSHEET_ID) {
    try {
        const metadata = await sheets.spreadsheets.get({ spreadsheetId });
        const existingSheets = metadata.data.sheets.map(s => s.properties.title);

        const requiredTabs = [
            '🌅 Morning Trips (Pickup)',
            '🌆 Evening Trips (Drop)',
            '📍 Real-Time Stops Log',
            '📊 Fleet KPI Summary'
        ];

        const addRequests = [];
        for (const tab of requiredTabs) {
            if (!existingSheets.includes(tab)) {
                addRequests.push({
                    addSheet: {
                        properties: {
                            title: tab,
                            gridProperties: { rowCount: 1500, columnCount: 22 }
                        }
                    }
                });
            }
        }

        if (addRequests.length > 0) {
            await sheets.spreadsheets.batchUpdate({
                spreadsheetId,
                requestBody: { requests: addRequests }
            });
            console.log('✅ Created missing Google Sheets tabs:', addRequests.map(r => r.addSheet.properties.title).join(', '));
        }

        // 1. Tab 1 Header: Morning Trips (Pickup)
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'🌅 Morning Trips (Pickup)'!A1:AA1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: {
                values: [[
                    'Trip ID', 'Date', 'Day', 'Bus No', 'Vehicle Plate', 'Official Route Name', 'Data Source',
                    'Origin Terminus', 'Movement Start', 'Scheduled Departure', 'Actual Departure', 'Scheduled Arrival', 'Actual Arrival',
                    'Duration (min)', 'Assigned Driver', 'Driver Phone', 'Stops Serviced', 'Distance (km)',
                    'Avg Speed (km/h)', 'GPS Samples', 'GPS Gaps', 'Telemetry Completeness %',
                    'Average Delay (min)', 'Punctuality Status', 'Delay (mins)', 'Trip Status', 'Direction'
                ]]
            }
        });

        // 2. Tab 2 Header: Evening Trips (Drop)
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A1:AA1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: {
                values: [[
                    'Trip ID', 'Date', 'Day', 'Bus No', 'Vehicle Plate', 'Return Route Name', 'Data Source',
                    'Origin (Campus)', 'Destination Terminus', 'Movement Start', 'Scheduled Departure', 'Actual Departure', 'Scheduled Arrival', 'Actual Arrival',
                    'Duration (min)', 'Assigned Driver', 'Driver Phone', 'Stops Serviced', 'Distance (km)',
                    'Avg Speed (km/h)', 'GPS Samples', 'GPS Gaps', 'Telemetry Completeness %',
                    'Average Delay (min)', 'Punctuality Status', 'Delay (mins)', 'Trip Status'
                ]]
            }
        });

        // 3. Tab 3 Header: Real-Time Stops Log
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'📍 Real-Time Stops Log'!A1:M1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: {
                values: [[
                    'Trip ID', 'Date', 'Shift', 'Data Source', 'Bus No', 'Vehicle Plate', 'Route Name',
                    'Stop S.No', 'Stop Name', 'Scheduled Time', 'Actual Reached Time',
                    'Variance', 'Stop Status'
                ]]
            }
        });

        // 4. Tab 4 Header: Fleet KPI Summary
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'📊 Fleet KPI Summary'!A1:K1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: {
                values: [[
                    'Date', 'Day', 'Total Fleet Buses', 'Morning Trips (Pickup)',
                    'Evening Trips (Drop)', 'Total Daily Trips', 'On-Time Rate %',
                    'Total Fleet Distance (km)', 'LIVE GPS / Sched Trips', 'Fleet Health', 'Last Synced At'
                ]]
            }
        });

        // Apply executive spreadsheet styling (frozen rows, column widths, banding, colors)
        await applyProfessionalSpreadsheetStyling(sheets, spreadsheetId);

        return true;
    } catch (e) {
        console.error('❌ Error initializing Google Sheets tabs:', e.message);
        throw e;
    }
}

/**
 * Applies executive styling across all Google Sheets tabs:
 * - Vibrant tab accent colors (Gold Amber, Twilight Violet, Emerald Teal, Cobalt Blue)
 * - Pinned frozen header rows + visible crisp gridlines
 * - Interactive Auto-Filter dropdowns on all columns
 * - Generous row heights (42px header, 28px data rows) for effortless readability
 * - Smart column alignments (LEFT for routes/names, CENTER for dates/times/status/metrics)
 * - Tailored, non-truncating column widths
 * - High-contrast institutional header color schemes
 * - Alternating zebra striping (Pure White #FFFFFF / Executive Slate #F8FAFC)
 * - Triple-tier conditional formatting (🟢 On-Time mint, 🔴 Delay rose, ⚡ In-Transit azure)
 */
async function applyProfessionalSpreadsheetStyling(sheets, spreadsheetId = SPREADSHEET_ID) {
    try {
        const meta = await sheets.spreadsheets.get({ spreadsheetId });
        const sheetMap = {};
        for (const s of meta.data.sheets) {
            sheetMap[s.properties.title] = s;
        }

        const requests = [];

        const configs = [
            {
                title: '🌅 Morning Trips (Pickup)',
                headerBg: { red: 0.06, green: 0.09, blue: 0.16 }, // #0F172A Deep Slate Navy
                tabColor: { red: 0.96, green: 0.62, blue: 0.04 }, // #F59E0B Golden Amber
                punctualityCol: 23,
                statusCol: 25,
                columnWidths: [190, 110, 95, 100, 130, 270, 160, 190, 130, 130, 130, 130, 130, 110, 160, 140, 110, 115, 120, 110, 100, 145, 130, 165, 110, 135, 135],
                leftCols: [0, 5, 7, 14],
                numCols: 27
            },
            {
                title: '🌆 Evening Trips (Drop)',
                headerBg: { red: 0.12, green: 0.11, blue: 0.29 }, // #1E1B4B Twilight Indigo
                tabColor: { red: 0.55, green: 0.36, blue: 0.96 }, // #8B5CF6 Twilight Purple
                punctualityCol: 24,
                statusCol: 26,
                columnWidths: [190, 110, 95, 100, 130, 280, 160, 190, 190, 130, 130, 130, 130, 130, 110, 160, 140, 110, 115, 120, 110, 100, 145, 130, 165, 110, 135],
                leftCols: [0, 5, 7, 8, 15],
                numCols: 27
            },
            {
                title: '📍 Real-Time Stops Log',
                headerBg: { red: 0.02, green: 0.31, blue: 0.23 }, // #064E3B Deep Forest Emerald
                tabColor: { red: 0.06, green: 0.73, blue: 0.51 }, // #10B981 Vibrant Mint
                punctualityCol: 11,
                statusCol: 12,
                columnWidths: [190, 110, 150, 160, 100, 130, 260, 90, 240, 120, 140, 130, 140],
                leftCols: [0, 6, 8], // Trip ID, Route Name, Stop Name
                numCols: 13
            },
            {
                title: '📊 Fleet KPI Summary',
                headerBg: { red: 0.12, green: 0.23, blue: 0.54 }, // #1E3A8A Executive Royal Blue
                tabColor: { red: 0.15, green: 0.39, blue: 0.92 }, // #2563EB Cobalt Blue
                punctualityCol: 6,
                statusCol: 9,
                columnWidths: [115, 105, 140, 155, 155, 140, 140, 165, 175, 150, 135],
                leftCols: [9], // Fleet Health
                numCols: 11
            }
        ];

        for (const cfg of configs) {
            const sheet = sheetMap[cfg.title];
            if (!sheet) continue;
            const sheetId = sheet.properties.sheetId;

            // 1. Tab Color, Freeze Top Row, and Enable Gridlines
            requests.push({
                updateSheetProperties: {
                    properties: {
                        sheetId,
                        tabColorStyle: {
                            rgbColor: cfg.tabColor
                        },
                        gridProperties: {
                            frozenRowCount: 1,
                            showGridLines: true
                        }
                    },
                    fields: 'tabColorStyle,gridProperties.frozenRowCount,gridProperties.showGridLines'
                }
            });

            // 2. Header Row Height (42px - Spacious Executive Touch)
            requests.push({
                updateDimensionProperties: {
                    range: { sheetId, dimension: 'ROWS', startIndex: 0, endIndex: 1 },
                    properties: { pixelSize: 42 },
                    fields: 'pixelSize'
                }
            });

            // 3. Data Rows Default Height (28px)
            requests.push({
                updateDimensionProperties: {
                    range: { sheetId, dimension: 'ROWS', startIndex: 1, endIndex: 500 },
                    properties: { pixelSize: 28 },
                    fields: 'pixelSize'
                }
            });

            // 4. Header Cell Styling (High-contrast, bold, centered, middle-aligned)
            requests.push({
                repeatCell: {
                    range: {
                        sheetId,
                        startRowIndex: 0,
                        endRowIndex: 1,
                        startColumnIndex: 0,
                        endColumnIndex: cfg.numCols
                    },
                    cell: {
                        userEnteredFormat: {
                            backgroundColor: cfg.headerBg,
                            textFormat: {
                                foregroundColor: { red: 1.0, green: 1.0, blue: 1.0 },
                                bold: true,
                                fontSize: 10.5,
                                fontFamily: 'Roboto'
                            },
                            horizontalAlignment: 'CENTER',
                            verticalAlignment: 'MIDDLE',
                            wrapStrategy: 'CLIP'
                        }
                    },
                    fields: 'userEnteredFormat(backgroundColor,textFormat,horizontalAlignment,verticalAlignment,wrapStrategy)'
                }
            });

            // 5. Data Rows Default Formatting (Roboto, vertical middle, centered by default)
            requests.push({
                repeatCell: {
                    range: {
                        sheetId,
                        startRowIndex: 1,
                        endRowIndex: 1000,
                        startColumnIndex: 0,
                        endColumnIndex: cfg.numCols
                    },
                    cell: {
                        userEnteredFormat: {
                            textFormat: {
                                foregroundColor: { red: 0.12, green: 0.15, blue: 0.20 },
                                fontSize: 9.5,
                                fontFamily: 'Roboto'
                            },
                            horizontalAlignment: 'CENTER',
                            verticalAlignment: 'MIDDLE',
                            wrapStrategy: 'CLIP'
                        }
                    },
                    fields: 'userEnteredFormat(textFormat,horizontalAlignment,verticalAlignment,wrapStrategy)'
                }
            });

            // 6. Left-align text columns (routes, stops, drivers) for superior readability
            for (const colIdx of cfg.leftCols) {
                requests.push({
                    repeatCell: {
                        range: {
                            sheetId,
                            startRowIndex: 1,
                            endRowIndex: 1000,
                            startColumnIndex: colIdx,
                            endColumnIndex: colIdx + 1
                        },
                        cell: {
                            userEnteredFormat: {
                                horizontalAlignment: 'LEFT'
                            }
                        },
                        fields: 'userEnteredFormat.horizontalAlignment'
                    }
                });
            }

            // 7. Column Widths (Generous, non-truncating)
            cfg.columnWidths.forEach((width, colIdx) => {
                requests.push({
                    updateDimensionProperties: {
                        range: {
                            sheetId,
                            dimension: 'COLUMNS',
                            startIndex: colIdx,
                            endIndex: colIdx + 1
                        },
                        properties: { pixelSize: width },
                        fields: 'pixelSize'
                    }
                });
            });

            // 8. Auto-Filter (Dropdown buttons for instant sorting & filtering by managers)
            requests.push({
                setBasicFilter: {
                    filter: {
                        range: {
                            sheetId,
                            startRowIndex: 0,
                            endRowIndex: 1000,
                            startColumnIndex: 0,
                            endColumnIndex: cfg.numCols
                        }
                    }
                }
            });

            // 9. Alternating Zebra Banding (White / #F8FAFC)
            if (!sheet.bandedRanges || sheet.bandedRanges.length === 0) {
                requests.push({
                    addBanding: {
                        bandedRange: {
                            range: {
                                sheetId,
                                startRowIndex: 0,
                                endRowIndex: 1000,
                                startColumnIndex: 0,
                                endColumnIndex: cfg.numCols
                            },
                            rowProperties: {
                                headerColor: cfg.headerBg,
                                firstBandColor: { red: 1.0, green: 1.0, blue: 1.0 },
                                secondBandColor: { red: 0.97, green: 0.98, blue: 0.99 } // Crisp #F8FAFC
                            }
                        }
                    }
                });
            }

            // 10. Conditional Formatting (Punctuality & Trip Status Badges)
            if (!sheet.conditionalFormats || sheet.conditionalFormats.length === 0) {
                // Rule A: Soft Mint for On-Time
                requests.push({
                    addConditionalFormatRule: {
                        rule: {
                            ranges: [{
                                sheetId,
                                startRowIndex: 1,
                                endRowIndex: 1000,
                                startColumnIndex: cfg.punctualityCol,
                                endColumnIndex: cfg.punctualityCol + 1
                            }],
                            booleanRule: {
                                condition: {
                                    type: 'TEXT_CONTAINS',
                                    values: [{ userEnteredValue: 'On-Time' }]
                                },
                                format: {
                                    backgroundColor: { red: 0.88, green: 0.95, blue: 0.89 }, // Soft Emerald Mint
                                    textFormat: {
                                        foregroundColor: { red: 0.08, green: 0.45, blue: 0.22 },
                                        bold: true
                                    }
                                }
                            }
                        },
                        index: 0
                    }
                });

                // Rule B: Soft Rose for Delay
                requests.push({
                    addConditionalFormatRule: {
                        rule: {
                            ranges: [{
                                sheetId,
                                startRowIndex: 1,
                                endRowIndex: 1000,
                                startColumnIndex: cfg.punctualityCol,
                                endColumnIndex: cfg.punctualityCol + 1
                            }],
                            booleanRule: {
                                condition: {
                                    type: 'TEXT_CONTAINS',
                                    values: [{ userEnteredValue: 'Delay' }]
                                },
                                format: {
                                    backgroundColor: { red: 0.99, green: 0.90, blue: 0.90 }, // Soft Rose Pink
                                    textFormat: {
                                        foregroundColor: { red: 0.72, green: 0.11, blue: 0.11 },
                                        bold: true
                                    }
                                }
                            }
                        },
                        index: 1
                    }
                });

                // Rule C: Soft Azure for In-Transit / Active
                requests.push({
                    addConditionalFormatRule: {
                        rule: {
                            ranges: [{
                                sheetId,
                                startRowIndex: 1,
                                endRowIndex: 1000,
                                startColumnIndex: cfg.punctualityCol,
                                endColumnIndex: cfg.punctualityCol + 1
                            }],
                            booleanRule: {
                                condition: {
                                    type: 'TEXT_CONTAINS',
                                    values: [{ userEnteredValue: 'In-Transit' }]
                                },
                                format: {
                                    backgroundColor: { red: 0.88, green: 0.94, blue: 1.0 }, // Soft Azure Blue
                                    textFormat: {
                                        foregroundColor: { red: 0.08, green: 0.35, blue: 0.75 },
                                        bold: true
                                    }
                                }
                            }
                        },
                        index: 2
                    }
                });
            }
        }

        if (requests.length > 0) {
            await sheets.spreadsheets.batchUpdate({
                spreadsheetId,
                requestBody: { requests }
            });
            console.log(`✨ Applied executive styling, vibrant tab colors, auto-filters, alignments, and banding across ${configs.length} Google Sheets tabs!`);
        }
    } catch (err) {
        console.warn('⚠️ Google Sheets styling batchUpdate warning (non-fatal):', err.message);
    }
}

function formatSheetDistance(distanceKm) {
    if (distanceKm === undefined || distanceKm === null || distanceKm === '' || distanceKm === 'N/A') {
        return 'N/A';
    }
    if (typeof distanceKm === 'number') {
        return `${distanceKm.toFixed(1)} km`;
    }
    const str = String(distanceKm);
    return str.includes('km') ? str : `${str} km`;
}

function fmtSheetIstTime(ts) {
    if (!ts) return 'NO DATA';
    const dt = new Date(ts);
    if (Number.isNaN(dt.getTime())) return String(ts);
    return dt.toLocaleTimeString('en-IN', {
        timeZone: 'Asia/Kolkata',
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
    });
}

function buildMorningSheetRow(t) {
    const dataSource = t.dataSource || 'SCHEDULED / ESTIMATED';
    const scheduledDeparture = t.scheduledDeparture || 'NO DATA';
    const actualDeparture = t.actualDeparture || 'NO DATA';
    const scheduledArrival = t.scheduledArrival || 'NO DATA';
    const actualArrival = t.actualArrival || 'NO DATA';
    const movementStart = t.movementStartTimestamp ? fmtSheetIstTime(t.movementStartTimestamp) : 'NO DATA';
    const distanceVal = t.actualDistanceKm !== undefined && t.actualDistanceKm !== null
        ? formatSheetDistance(t.actualDistanceKm)
        : formatSheetDistance(t.distanceKm);
    const durationVal = t.totalDurationMinutes !== undefined && t.totalDurationMinutes !== null
        ? t.totalDurationMinutes
        : (t.duration || 'NO DATA');

    return [
        t.tripId || '',
        t.date,
        t.day,
        t.busNo,
        t.busNumber || t.vehicleNo || 'N/A',
        t.routeName,
        dataSource,
        t.originStop,
        movementStart,
        scheduledDeparture,
        actualDeparture,
        scheduledArrival,
        actualArrival,
        durationVal,
        t.driverName,
        t.driverPhone,
        t.stopsCompleted,
        distanceVal,
        t.averageSpeedKmh ?? 'NO DATA',
        t.validGpsSamples ?? t.gpsSampleCount ?? 0,
        t.gpsGapCount ?? 0,
        t.telemetryCompletenessPercent ?? 'NO DATA',
        t.averageDelayMinutes ?? 'NO DATA',
        t.punctuality,
        t.delayMinutes !== undefined ? (t.delayMinutes > 0 ? `+${t.delayMinutes} min` : '0 min') : '0 min',
        t.status,
        t.direction || 'stops -> campus'
    ];
}

function buildEveningSheetRow(t) {
    const dataSource = t.dataSource || 'SCHEDULED / ESTIMATED';
    const scheduledDeparture = t.scheduledDeparture || 'NO DATA';
    const actualDeparture = t.actualDeparture || 'NO DATA';
    const scheduledArrival = t.scheduledArrival || 'NO DATA';
    const actualArrival = t.actualArrival || 'NO DATA';
    const movementStart = t.movementStartTimestamp ? fmtSheetIstTime(t.movementStartTimestamp) : 'NO DATA';
    const distanceVal = t.actualDistanceKm !== undefined && t.actualDistanceKm !== null
        ? formatSheetDistance(t.actualDistanceKm)
        : formatSheetDistance(t.distanceKm);
    const durationVal = t.totalDurationMinutes !== undefined && t.totalDurationMinutes !== null
        ? t.totalDurationMinutes
        : (t.duration || 'NO DATA');

    return [
        t.tripId || '',
        t.date,
        t.day,
        t.busNo,
        t.busNumber || t.vehicleNo || 'N/A',
        t.routeName,
        dataSource,
        t.originStop || 'SISTec Ratibad Campus',
        t.destinationStop,
        movementStart,
        scheduledDeparture,
        actualDeparture,
        scheduledArrival,
        actualArrival,
        durationVal,
        t.driverName,
        t.driverPhone,
        t.stopsCompleted,
        distanceVal,
        t.averageSpeedKmh ?? 'NO DATA',
        t.validGpsSamples ?? t.gpsSampleCount ?? 0,
        t.gpsGapCount ?? 0,
        t.telemetryCompletenessPercent ?? 'NO DATA',
        t.averageDelayMinutes ?? 'NO DATA',
        t.punctuality,
        t.delayMinutes !== undefined ? (t.delayMinutes > 0 ? `+${t.delayMinutes} min` : '0 min') : '0 min',
        t.status
    ];
}

function buildStopSheetRow(s) {
    return [
        s.tripId || '',
        s.date,
        s.shift,
        s.dataSource || 'SCHEDULED / ESTIMATED',
        s.busNo,
        s.vehicleNo,
        s.routeName,
        s.stopNo,
        s.stopName,
        s.scheduledTime,
        s.actualTime || 'NO DATA',
        s.variance,
        s.status
    ];
}

function buildKpiSheetRow(reportData, targetDate, syncTime) {
    const totalTrips = reportData.totalTrips ?? ((reportData.morningTrips?.length || 0) + (reportData.eveningTrips?.length || 0));
    const morningCount = reportData.morningTrips?.length || 0;
    const eveningCount = reportData.eveningTrips?.length || 0;
    const liveCount = reportData.liveGpsTrips ?? 0;
    const schedCount = reportData.scheduledEstimatedTrips ?? Math.max(0, totalTrips - liveCount);
    const punctualityRate = reportData.punctualityRate !== undefined ? `${reportData.punctualityRate}%` : '100.0%';
    const totalDistance = reportData.totalDistance !== undefined ? `${reportData.totalDistance} km` : '0.0 km';

    return [
        targetDate,
        reportData.day,
        `${reportData.totalBuses || 0} Buses`,
        `${morningCount} Trips`,
        `${eveningCount} Trips`,
        `${totalTrips} Trips`,
        punctualityRate,
        totalDistance,
        `${liveCount} Live / ${schedCount} Sched`,
        liveCount > 0 ? '🟢 Live GPS Active' : '⚪ Timetable Mode',
        `${syncTime} IST`
    ];
}

/**
 * Syncs full Daily Reports (Morning + Evening + Stops + KPI) to Google Sheets
 * @param {Object} reportData Data object returned from generateTripReportData()
 */
async function syncDailyTripReportsToGoogleSheets(reportData, targetDate, spreadsheetId = SPREADSHEET_ID) {
    try {
        const auth = getAuthClient();
        const sheets = google.sheets({ version: 'v4', auth });

        await initializeSpreadsheetTabs(sheets, spreadsheetId);

        const syncTime = new Date().toLocaleTimeString('en-IN', {
            timeZone: 'Asia/Kolkata',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: true
        });

        // Natural sort by Bus Number (Bus 01 -> Bus 27), then tripSequence
        const parseBusNum = str => parseInt(String(str).replace(/[^0-9]/g, ''), 10) || 0;
        const sortTrips = (a, b) => {
            const busDiff = parseBusNum(a.busNo) - parseBusNum(b.busNo);
            if (busDiff !== 0) return busDiff;
            return (a.tripSequence || 1) - (b.tripSequence || 1);
        };
        const sortedMorning = [...(reportData.morningTrips || [])].sort(sortTrips);
        const sortedEvening = [...(reportData.eveningTrips || [])].sort(sortTrips);

        const morningRows = sortedMorning.map(buildMorningSheetRow);
        const eveningRows = sortedEvening.map(buildEveningSheetRow);
        const stopRows = (reportData.stopLogs || []).map(buildStopSheetRow);

        // 1. Update Morning Trips Sheet (Date is col B / index 1)
        const existingMorning = await sheets.spreadsheets.values.get({
            spreadsheetId,
            range: `'🌅 Morning Trips (Pickup)'!A2:AA`
        });
        let curMorning = (existingMorning.data.values || []).filter(r => r[1] !== targetDate);
        curMorning.push(...morningRows);

        await sheets.spreadsheets.values.clear({
            spreadsheetId,
            range: `'🌅 Morning Trips (Pickup)'!A2:AA1000`
        });
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'🌅 Morning Trips (Pickup)'!A2`,
            valueInputOption: 'USER_ENTERED',
            requestBody: { values: curMorning }
        });

        // 2. Update Evening Trips Sheet (Date is col B / index 1)
        const existingEvening = await sheets.spreadsheets.values.get({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A2:AA`
        });
        let curEvening = (existingEvening.data.values || []).filter(r => r[1] !== targetDate);
        curEvening.push(...eveningRows);

        await sheets.spreadsheets.values.clear({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A2:AA1000`
        });
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A2`,
            valueInputOption: 'USER_ENTERED',
            requestBody: { values: curEvening }
        });

        // 3. Update Stop Timestamps Log Sheet (Date is col B / index 1)
        if (stopRows.length > 0) {
            const existingStops = await sheets.spreadsheets.values.get({
                spreadsheetId,
                range: `'📍 Real-Time Stops Log'!A2:M`
            });
            let curStops = (existingStops.data.values || []).filter(r => r[1] !== targetDate);
            curStops.push(...stopRows);

            await sheets.spreadsheets.values.clear({
                spreadsheetId,
                range: `'📍 Real-Time Stops Log'!A2:M3000`
            });
            await sheets.spreadsheets.values.update({
                spreadsheetId,
                range: `'📍 Real-Time Stops Log'!A2`,
                valueInputOption: 'USER_ENTERED',
                requestBody: { values: curStops }
            });
        }

        // 4. Update Fleet KPI Summary Sheet from canonical reportData
        const kpiRow = buildKpiSheetRow(reportData, targetDate, syncTime);

        const existingKpi = await sheets.spreadsheets.values.get({
            spreadsheetId,
            range: `'📊 Fleet KPI Summary'!A2:K`
        });
        let curKpi = (existingKpi.data.values || []).filter(r => r[0] !== targetDate);
        curKpi.push(kpiRow);

        await sheets.spreadsheets.values.clear({
            spreadsheetId,
            range: `'📊 Fleet KPI Summary'!A2:K200`
        });
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'📊 Fleet KPI Summary'!A2`,
            valueInputOption: 'USER_ENTERED',
            requestBody: { values: curKpi }
        });

        // Re-apply professional styling and auto-filters across updated ranges
        await applyProfessionalSpreadsheetStyling(sheets, spreadsheetId);

        console.log(`✅ Google Sheets Sync Successful: ${morningRows.length} Morning + ${eveningRows.length} Evening + ${stopRows.length} Stops Logged!`);

        return {
            success: true,
            syncedMorning: morningRows.length,
            syncedEvening: eveningRows.length,
            syncedStops: stopRows.length,
            spreadsheetUrl: `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit`
        };
    } catch (e) {
        console.error('❌ Error syncing to Google Sheets:', e);
        return {
            success: false,
            error: e.message
        };
    }
}

module.exports = {
    getAuthClient,
    buildMorningSheetRow,
    buildEveningSheetRow,
    buildStopSheetRow,
    buildKpiSheetRow,
    syncDailyTripReportsToGoogleSheets,
    initializeSpreadsheetTabs,
    SPREADSHEET_ID
};
