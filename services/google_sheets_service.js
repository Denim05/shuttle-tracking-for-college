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
            range: `'🌅 Morning Trips (Pickup)'!A1:Q1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: {
                values: [[
                    'Date', 'Day', 'Bus No', 'Vehicle Plate', 'Official Route Name', 
                    'Origin Terminus', 'Scheduled Start', 'Campus Arrival', 'Trip Duration', 
                    'Assigned Driver', 'Driver Phone', 'Total Stops', 'Road Dist (km)', 
                    'Punctuality Status', 'Delay (mins)', 'Trip Status', 'Last Synced At'
                ]]
            }
        });

        // 2. Tab 2 Header: Evening Trips (Drop)
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A1:Q1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: {
                values: [[
                    'Date', 'Day', 'Bus No', 'Vehicle Plate', 'Return Route Name', 
                    'Origin (Campus)', 'Campus Departure', 'Destination Terminus', 'Scheduled Arrival', 
                    'Trip Duration', 'Assigned Driver', 'Driver Phone', 'Total Stops', 
                    'Road Dist (km)', 'Punctuality Status', 'Delay (mins)', 'Trip Status'
                ]]
            }
        });

        // 3. Tab 3 Header: Real-Time Stops Log
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'📍 Real-Time Stops Log'!A1:K1`,
            valueInputOption: 'USER_ENTERED',
            requestBody: {
                values: [[
                    'Date', 'Shift', 'Bus No', 'Vehicle Plate', 'Route Name', 
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
                    'Total Fleet Distance (km)', 'Drivers Assigned', 'Fleet Health', 'Last Synced At'
                ]]
            }
        });

        return true;
    } catch (e) {
        console.error('❌ Error initializing Google Sheets tabs:', e.message);
        throw e;
    }
}

/**
 * Syncs full 2-Trip Daily Reports (Morning + Evening + Stops + KPI) to Google Sheets
 * @param {Object} reportData Data object returned from generateTripReportData()
 */
async function syncDailyTripReportsToGoogleSheets(reportData, targetDate) {
    try {
        const auth = getAuthClient();
        const sheets = google.sheets({ version: 'v4', auth });
        const spreadsheetId = SPREADSHEET_ID;

        await initializeSpreadsheetTabs(sheets, spreadsheetId);

        const syncTime = new Date().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: true });

        // Format Morning Rows
        const morningRows = (reportData.morningTrips || []).map(t => [
            t.date,
            t.day,
            t.busNo,
            t.vehicleNo,
            t.routeName,
            t.originStop,
            t.departureTime,
            t.arrivalTime,
            t.duration,
            t.driverName,
            t.driverPhone,
            t.stopsCompleted,
            t.distanceKm,
            t.punctuality,
            t.delayMinutes !== undefined ? t.delayMinutes : 0,
            t.status,
            syncTime
        ]);

        // Format Evening Rows
        const eveningRows = (reportData.eveningTrips || []).map(t => [
            t.date,
            t.day,
            t.busNo,
            t.vehicleNo,
            t.routeName,
            t.originStop || 'Ratibad Campus',
            t.departureTime,
            t.destinationStop,
            t.arrivalTime,
            t.duration,
            t.driverName,
            t.driverPhone,
            t.stopsCompleted,
            t.distanceKm,
            t.punctuality,
            t.delayMinutes !== undefined ? t.delayMinutes : 0,
            t.status
        ]);

        // Format Stop Log Rows
        const stopRows = (reportData.stopLogs || []).map(s => [
            s.date,
            s.shift,
            s.busNo,
            s.vehicleNo,
            s.routeName,
            s.stopNo,
            s.stopName,
            s.scheduledTime,
            s.actualTime,
            s.variance,
            s.status
        ]);

        // 1. Update Morning Trips Sheet
        const existingMorning = await sheets.spreadsheets.values.get({
            spreadsheetId,
            range: `'🌅 Morning Trips (Pickup)'!A2:Q`
        });
        let curMorning = (existingMorning.data.values || []).filter(r => r[0] !== targetDate);
        curMorning.push(...morningRows);

        await sheets.spreadsheets.values.clear({
            spreadsheetId,
            range: `'🌅 Morning Trips (Pickup)'!A2:Q1000`
        });
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'🌅 Morning Trips (Pickup)'!A2`,
            valueInputOption: 'USER_ENTERED',
            requestBody: { values: curMorning }
        });

        // 2. Update Evening Trips Sheet
        const existingEvening = await sheets.spreadsheets.values.get({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A2:Q`
        });
        let curEvening = (existingEvening.data.values || []).filter(r => r[0] !== targetDate);
        curEvening.push(...eveningRows);

        await sheets.spreadsheets.values.clear({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A2:Q1000`
        });
        await sheets.spreadsheets.values.update({
            spreadsheetId,
            range: `'🌆 Evening Trips (Drop)'!A2`,
            valueInputOption: 'USER_ENTERED',
            requestBody: { values: curEvening }
        });

        // 3. Update Stop Timestamps Log Sheet (keep up to date)
        if (stopRows.length > 0) {
            const existingStops = await sheets.spreadsheets.values.get({
                spreadsheetId,
                range: `'📍 Real-Time Stops Log'!A2:K`
            });
            let curStops = (existingStops.data.values || []).filter(r => r[0] !== targetDate);
            curStops.push(...stopRows);

            await sheets.spreadsheets.values.clear({
                spreadsheetId,
                range: `'📍 Real-Time Stops Log'!A2:K3000`
            });
            await sheets.spreadsheets.values.update({
                spreadsheetId,
                range: `'📍 Real-Time Stops Log'!A2`,
                valueInputOption: 'USER_ENTERED',
                requestBody: { values: curStops }
            });
        }

        // 4. Update Fleet KPI Summary Sheet
        const totalTrips = morningRows.length + eveningRows.length;
        const onTimeMorning = morningRows.filter(r => String(r[13]).includes('On-Time')).length;
        const onTimeEvening = eveningRows.filter(r => String(r[14]).includes('On-Time')).length;
        const punctualityRate = totalTrips > 0 ? (((onTimeMorning + onTimeEvening) / totalTrips) * 100).toFixed(1) + '%' : '100.0%';
        const totalKm = (reportData.morningTrips || []).reduce((acc, t) => acc + (parseFloat(t.distanceKm) || 0), 0) +
                        (reportData.eveningTrips || []).reduce((acc, t) => acc + (parseFloat(t.distanceKm) || 0), 0);

        const kpiRow = [
            targetDate,
            reportData.day,
            reportData.totalBuses || 27,
            morningRows.length,
            eveningRows.length,
            totalTrips,
            punctualityRate,
            totalKm.toFixed(1),
            reportData.totalBuses || 27,
            '100% Operational',
            syncTime
        ];

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
    syncDailyTripReportsToGoogleSheets,
    initializeSpreadsheetTabs,
    SPREADSHEET_ID
};
