const path = require('path');
const XLSX = require(path.resolve(__dirname, '..', '..', 'web_dashboard', 'node_modules', 'xlsx'));
const fs = require('fs');

function excelTimeToString(val) {
    if (typeof val === 'number') {
        const totalMinutes = Math.round(val * 24 * 60);
        let hours = Math.floor(totalMinutes / 60);
        const mins = totalMinutes % 60;
        const ampm = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12;
        if (hours === 0) hours = 12;
        return hours.toString().padStart(2, '0') + ':' + mins.toString().padStart(2, '0') + ' ' + ampm;
    }
    return String(val || '').trim();
}

function parseTimetableExcel() {
    const filePath = path.resolve(__dirname, '..', '..', 'TIME - New Update Bus Route  19-08-2025 111111.xlsx');
    if (!fs.existsSync(filePath)) {
        throw new Error('File not found: ' + filePath);
    }

    const workbook = XLSX.readFile(filePath);
    const sheet = workbook.Sheets['ALL BUSES'] || workbook.Sheets[workbook.SheetNames[0]];
    const rows = XLSX.utils.sheet_to_json(sheet, { header: 1 });

    const buses = [];
    let current = null;

    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (!row || row.length === 0) continue;
        const rowStr = row.map(c => String(c)).join(' ').trim();

        // Detect new bus block start by 'Vehicle No' or 'ECCO'
        if (/Vehicle\s*No/i.test(rowStr) || /ECCO/i.test(rowStr)) {
            if (current && (current.busNo || current.stops.length > 0)) {
                buses.push(current);
            }
            current = {
                busNo: '',
                vehicleNo: '',
                routeName: '',
                driverName: '',
                driverPhone: '',
                stops: []
            };

            const vMatch = rowStr.match(/Vehicle\s*No\s*[:\.]\s*([A-Za-z0-9\s]+?)(?:\s{2,}|Route|$)/i);
            if (vMatch) current.vehicleNo = vMatch[1].trim();

            const rMatch = rowStr.match(/(?:Vehicle\s*No\s*[:\.].*?)\s+([A-Za-z0-9\s\+\-]+\s*Route|[A-Za-z\s]+Route)/i);
            if (rMatch) {
                current.routeName = rMatch[1].trim();
            } else if (/ECCO/i.test(rowStr)) {
                current.routeName = 'Icchawar Route (Pvt ECCO)';
                current.busNo = 'ECCO (Pvt)';
            }
        }

        if (current && (/Bus\s*No/i.test(rowStr) || /ECCO/i.test(rowStr))) {
            const bMatch = rowStr.match(/Bus\s*No\s*[:\.]\s*([A-Za-z0-9\-\s\+]+?)(?:\s{2,}|Effective|$)/i);
            if (bMatch) {
                current.busNo = bMatch[1].trim();
            } else if (/ECCO/i.test(rowStr)) {
                current.busNo = 'ECCO (Pvt)';
            }
        }

        // Parse individual stops
        if (current && typeof row[0] === 'number' && row[1]) {
            current.stops.push({
                sNo: row[0],
                name: String(row[1]).trim(),
                time: excelTimeToString(row[2])
            });
        }

        // Parse driver details
        if (current && (/Driver/i.test(rowStr) || /Mob/i.test(rowStr))) {
            const dMatch = rowStr.match(/Driver\s*:\s*([A-Za-z\s]+?)(?:Mob|\-|\:|\d|$)/i);
            const pMatch = rowStr.match(/(?:Mob|\-|\:)\s*(\d{10})/i) || rowStr.match(/(\d{10})/);
            if (dMatch && !current.driverName) {
                current.driverName = dMatch[1].trim().replace(/\s+/g, ' ');
            }
            if (pMatch && !current.driverPhone) {
                current.driverPhone = pMatch[1].trim();
            }
        }
    }

    if (current && (current.busNo || current.stops.length > 0)) {
        buses.push(current);
    }

    return buses;
}

if (require.main === module) {
    const buses = parseTimetableExcel();
    console.log('Extracted buses count:', buses.length);
    buses.forEach((b, idx) => {
        const origin = b.stops[0] ? b.stops[0].name + ' (' + b.stops[0].time + ')' : 'N/A';
        const dest = b.stops[b.stops.length - 1] ? b.stops[b.stops.length - 1].name + ' (' + b.stops[b.stops.length - 1].time + ')' : 'N/A';
        console.log(`[${idx + 1}] Bus ${b.busNo} | Plate: ${b.vehicleNo} | Route: ${b.routeName} | Driver: ${b.driverName} (${b.driverPhone}) | Stops: ${b.stops.length} | ${origin} -> ${dest}`);
    });
}

module.exports = { parseTimetableExcel, excelTimeToString };
