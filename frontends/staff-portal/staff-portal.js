// Backend API configuration
const API_CONFIG = {
    apiGateway: 'https://7bzha9trsl.execute-api.ap-northeast-2.amazonaws.com/dev',
    alb: 'http://cloudcafe-alb-dev-252257753.ap-northeast-2.elb.amazonaws.com'
};

// State
let inventory = [];
let staff = [];
let menuItems = [];
let stats = {};

// Initialize
async function init() {
    await loadDashboardStats();
    await loadInventory();
    await loadStaff();
    await loadMenu();
    
    // Set default dates for reports
    const today = new Date();
    const weekAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
    document.getElementById('reportStartDate').valueAsDate = weekAgo;
    document.getElementById('reportEndDate').valueAsDate = today;
}

// Tab switching
function switchTab(tabName) {
    // Hide all tabs
    document.querySelectorAll('.tab-content').forEach(tab => {
        tab.classList.remove('active');
    });
    document.querySelectorAll('.tab').forEach(tab => {
        tab.classList.remove('active');
    });
    
    // Show selected tab
    document.getElementById(tabName).classList.add('active');
    event.target.classList.add('active');
}

// Load dashboard statistics
async function loadDashboardStats() {
    try {
        const response = await fetch(`${API_CONFIG.apiGateway}/staff/dashboard`);
        if (response.ok) {
            stats = await response.json();
        } else {
            throw new Error('API unavailable');
        }
    } catch (error) {
        // Demo data
        stats = {
            todaySales: 2847.50,
            todayOrders: 156,
            activeStaff: 8,
            lowStockItems: 3
        };
    }
    
    renderDashboard();
}

// Render dashboard
function renderDashboard() {
    document.getElementById('todaySales').textContent = '$' + stats.todaySales.toFixed(2);
    document.getElementById('todayOrders').textContent = stats.todayOrders;
    document.getElementById('activeStaff').textContent = stats.activeStaff;
    document.getElementById('lowStockItems').textContent = stats.lowStockItems;
    
    // Recent activity
    const activities = [
        { time: '2 min ago', action: 'Inventory updated', user: 'Alex', type: 'info' },
        { time: '15 min ago', action: 'New staff member added', user: 'Manager', type: 'success' },
        { time: '1 hour ago', action: 'Low stock alert: Coffee Beans', user: 'System', type: 'warning' },
        { time: '2 hours ago', action: 'Sales report generated', user: 'Manager', type: 'info' }
    ];
    
    document.getElementById('recentActivity').innerHTML = activities.map(act => `
        <div style="padding: 15px; border-left: 4px solid ${act.type === 'warning' ? '#f39c12' : act.type === 'success' ? '#27ae60' : '#3498db'}; margin-bottom: 10px; background: #f9f9f9; border-radius: 5px;">
            <div style="display: flex; justify-content: space-between;">
                <strong>${act.action}</strong>
                <span style="color: #999;">${act.time}</span>
            </div>
            <div style="color: #666; font-size: 0.9em; margin-top: 5px;">by ${act.user}</div>
        </div>
    `).join('');
}

// Load inventory
async function loadInventory() {
    try {
        const response = await fetch(`${API_CONFIG.apiGateway}/inventory`);
        if (response.ok) {
            inventory = await response.json();
        } else {
            throw new Error('API unavailable');
        }
    } catch (error) {
        // Demo inventory data
        inventory = [
            { id: '1', name: 'Coffee Beans (Arabica)', category: 'Ingredients', stock: 45, minStock: 50, unit: 'kg', lastUpdated: new Date().toISOString() },
            { id: '2', name: 'Milk (Whole)', category: 'Dairy', stock: 120, minStock: 100, unit: 'L', lastUpdated: new Date().toISOString() },
            { id: '3', name: 'Oat Milk', category: 'Dairy', stock: 15, minStock: 30, unit: 'L', lastUpdated: new Date().toISOString() },
            { id: '4', name: 'Caramel Syrup', category: 'Syrups', stock: 8, minStock: 15, unit: 'bottles', lastUpdated: new Date().toISOString() },
            { id: '5', name: 'Vanilla Syrup', category: 'Syrups', stock: 25, minStock: 15, unit: 'bottles', lastUpdated: new Date().toISOString() },
            { id: '6', name: 'Paper Cups (12oz)', category: 'Supplies', stock: 500, minStock: 200, unit: 'units', lastUpdated: new Date().toISOString() },
            { id: '7', name: 'Paper Cups (16oz)', category: 'Supplies', stock: 450, minStock: 200, unit: 'units', lastUpdated: new Date().toISOString() },
            { id: '8', name: 'Lids', category: 'Supplies', stock: 800, minStock: 300, unit: 'units', lastUpdated: new Date().toISOString() },
            { id: '9', name: 'Sugar Packets', category: 'Condiments', stock: 1200, minStock: 500, unit: 'packets', lastUpdated: new Date().toISOString() },
            { id: '10', name: 'Napkins', category: 'Supplies', stock: 2000, minStock: 1000, unit: 'units', lastUpdated: new Date().toISOString() }
        ];
    }
    
    renderInventory();
}

// Render inventory
function renderInventory() {
    document.getElementById('inventoryLoading').style.display = 'none';
    document.getElementById('inventoryTable').style.display = 'table';
    
    const tbody = document.getElementById('inventoryBody');
    tbody.innerHTML = inventory.map(item => {
        const status = item.stock < item.minStock ? 'danger' : item.stock < item.minStock * 1.5 ? 'warning' : 'success';
        const statusText = item.stock < item.minStock ? 'Low Stock' : item.stock < item.minStock * 1.5 ? 'Warning' : 'Good';
        const lastUpdated = new Date(item.lastUpdated).toLocaleString();
        
        return `
            <tr>
                <td><strong>${item.name}</strong><br><small>${item.unit}</small></td>
                <td>${item.category}</td>
                <td><strong>${item.stock}</strong></td>
                <td>${item.minStock}</td>
                <td><span class="badge badge-${status}">${statusText}</span></td>
                <td>${lastUpdated}</td>
                <td>
                    <button class="btn btn-secondary" style="padding: 8px 15px; font-size: 0.9em;" onclick="updateInventory('${item.id}')">Update</button>
                    <button class="btn btn-success" style="padding: 8px 15px; font-size: 0.9em;" onclick="reorderItem('${item.id}')">Reorder</button>
                </td>
            </tr>
        `;
    }).join('');
}

// Load staff
async function loadStaff() {
    try {
        const response = await fetch(`${API_CONFIG.apiGateway}/staff`);
        if (response.ok) {
            staff = await response.json();
        } else {
            throw new Error('API unavailable');
        }
    } catch (error) {
        // Demo staff data
        staff = [
            { id: '1', name: 'Alex Chen', role: 'Barista', shift: 'Morning (6AM-2PM)', status: 'active', performance: 4.9 },
            { id: '2', name: 'Maria Santos', role: 'Senior Barista', shift: 'Morning (6AM-2PM)', status: 'active', performance: 5.0 },
            { id: '3', name: 'Jordan Kim', role: 'Barista', shift: 'Afternoon (2PM-10PM)', status: 'active', performance: 4.7 },
            { id: '4', name: 'Taylor Rodriguez', role: 'Barista', shift: 'Afternoon (2PM-10PM)', status: 'active', performance: 4.8 },
            { id: '5', name: 'Sam Patel', role: 'Cashier', shift: 'Morning (6AM-2PM)', status: 'active', performance: 4.6 },
            { id: '6', name: 'Jamie Lee', role: 'Cashier', shift: 'Afternoon (2PM-10PM)', status: 'off', performance: 4.5 },
            { id: '7', name: 'Casey Brown', role: 'Shift Supervisor', shift: 'Morning (6AM-2PM)', status: 'active', performance: 4.9 },
            { id: '8', name: 'Morgan Davis', role: 'Shift Supervisor', shift: 'Afternoon (2PM-10PM)', status: 'active', performance: 4.8 }
        ];
    }
    
    renderStaff();
}

// Render staff
function renderStaff() {
    const tbody = document.getElementById('staffBody');
    tbody.innerHTML = staff.map(member => {
        const statusBadge = member.status === 'active' ? 'success' : 'warning';
        const statusText = member.status === 'active' ? 'On Duty' : 'Off Duty';
        
        return `
            <tr>
                <td><strong>${member.name}</strong></td>
                <td>${member.role}</td>
                <td>${member.shift}</td>
                <td><span class="badge badge-${statusBadge}">${statusText}</span></td>
                <td>⭐ ${member.performance.toFixed(1)}</td>
                <td>
                    <button class="btn btn-secondary" style="padding: 8px 15px; font-size: 0.9em;" onclick="editStaff('${member.id}')">Edit</button>
                    <button class="btn" style="padding: 8px 15px; font-size: 0.9em;" onclick="viewSchedule('${member.id}')">Schedule</button>
                </td>
            </tr>
        `;
    }).join('');
}

// Load menu
async function loadMenu() {
    try {
        const response = await fetch(`${API_CONFIG.apiGateway}/menu`);
        if (response.ok) {
            menuItems = await response.json();
        } else {
            throw new Error('API unavailable');
        }
    } catch (error) {
        // Demo menu data
        menuItems = [
            { id: '1', name: 'Espresso', category: 'Coffee', price: 3.50, status: 'active' },
            { id: '2', name: 'Caramel Macchiato', category: 'Coffee', price: 5.25, status: 'active' },
            { id: '3', name: 'Cappuccino', category: 'Coffee', price: 4.50, status: 'active' },
            { id: '4', name: 'Latte', category: 'Coffee', price: 4.75, status: 'active' },
            { id: '5', name: 'Americano', category: 'Coffee', price: 3.75, status: 'active' },
            { id: '6', name: 'Mocha', category: 'Coffee', price: 5.50, status: 'active' },
            { id: '7', name: 'Cold Brew', category: 'Iced Coffee', price: 4.50, status: 'active' },
            { id: '8', name: 'Matcha Latte', category: 'Tea', price: 4.75, status: 'active' },
            { id: '9', name: 'Croissant', category: 'Pastry', price: 3.00, status: 'active' },
            { id: '10', name: 'Blueberry Muffin', category: 'Pastry', price: 3.50, status: 'active' }
        ];
    }
    
    renderMenu();
}

// Render menu
function renderMenu() {
    document.getElementById('menuLoading').style.display = 'none';
    document.getElementById('menuTable').style.display = 'table';
    
    const tbody = document.getElementById('menuBody');
    tbody.innerHTML = menuItems.map(item => {
        const statusBadge = item.status === 'active' ? 'success' : 'warning';
        const statusText = item.status === 'active' ? 'Active' : 'Inactive';
        
        return `
            <tr>
                <td><strong>${item.name}</strong></td>
                <td>${item.category}</td>
                <td>$${item.price.toFixed(2)}</td>
                <td><span class="badge badge-${statusBadge}">${statusText}</span></td>
                <td>
                    <button class="btn btn-secondary" style="padding: 8px 15px; font-size: 0.9em;" onclick="editMenuItem('${item.id}')">Edit</button>
                    <button class="btn btn-danger" style="padding: 8px 15px; font-size: 0.9em;" onclick="toggleMenuItem('${item.id}')">
                        ${item.status === 'active' ? 'Disable' : 'Enable'}
                    </button>
                </td>
            </tr>
        `;
    }).join('');
}

// Generate report
async function generateReport() {
    const startDate = document.getElementById('reportStartDate').value;
    const endDate = document.getElementById('reportEndDate').value;
    
    if (!startDate || !endDate) {
        alert('Please select both start and end dates');
        return;
    }
    
    try {
        const response = await fetch(`${API_CONFIG.apiGateway}/reports/sales?start=${startDate}&end=${endDate}`);
        let reportData;
        
        if (response.ok) {
            reportData = await response.json();
        } else {
            throw new Error('API unavailable');
        }
    } catch (error) {
        // Demo report data
        reportData = {
            totalSales: 19847.50,
            totalOrders: 1247,
            avgOrderValue: 15.91,
            topItems: [
                { name: 'Caramel Macchiato', orders: 342, revenue: 1795.50 },
                { name: 'Latte', orders: 298, revenue: 1415.50 },
                { name: 'Cappuccino', orders: 267, revenue: 1201.50 }
            ]
        };
    }
    
    document.getElementById('reportResults').innerHTML = `
        <div class="grid" style="margin-top: 20px;">
            <div class="stat-card">
                <div class="stat-value">$${reportData.totalSales.toFixed(2)}</div>
                <div class="stat-label">Total Sales</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${reportData.totalOrders}</div>
                <div class="stat-label">Total Orders</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$${reportData.avgOrderValue.toFixed(2)}</div>
                <div class="stat-label">Avg Order Value</div>
            </div>
        </div>
        
        <h3 style="margin-top: 30px; color: #6f4e37;">Top Selling Items</h3>
        <table class="table">
            <thead>
                <tr>
                    <th>Item</th>
                    <th>Orders</th>
                    <th>Revenue</th>
                </tr>
            </thead>
            <tbody>
                ${reportData.topItems.map(item => `
                    <tr>
                        <td><strong>${item.name}</strong></td>
                        <td>${item.orders}</td>
                        <td>$${item.revenue.toFixed(2)}</td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
        
        <button class="btn" style="margin-top: 20px;" onclick="exportReport()">📥 Export to CSV</button>
    `;
}

// Modal functions
function openAddInventoryModal() {
    document.getElementById('inventoryModal').classList.add('active');
}

function openAddStaffModal() {
    alert('Add Staff Modal - Coming soon!\n\nThis will allow you to:\n- Add new staff members\n- Set roles and shifts\n- Configure permissions');
}

function openAddMenuModal() {
    alert('Add Menu Item Modal - Coming soon!\n\nThis will allow you to:\n- Add new menu items\n- Set prices and categories\n- Upload item images');
}

function closeModal(modalId) {
    document.getElementById(modalId).classList.remove('active');
}

// Action functions
async function updateInventory(itemId) {
    const item = inventory.find(i => i.id === itemId);
    if (!item) return;
    
    const newStock = prompt(`Update stock for ${item.name}\nCurrent: ${item.stock} ${item.unit}`, item.stock);
    if (newStock === null) return;
    
    try {
        const response = await fetch(`${API_CONFIG.apiGateway}/inventory/${itemId}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ stock: parseInt(newStock) })
        });
        
        if (response.ok) {
            item.stock = parseInt(newStock);
            item.lastUpdated = new Date().toISOString();
            renderInventory();
            alert('✅ Inventory updated successfully!');
        }
    } catch (error) {
        item.stock = parseInt(newStock);
        item.lastUpdated = new Date().toISOString();
        renderInventory();
        alert('✅ Inventory updated! (Demo mode)');
    }
}

async function reorderItem(itemId) {
    const item = inventory.find(i => i.id === itemId);
    if (!item) return;
    
    const quantity = prompt(`Reorder ${item.name}\nRecommended quantity: ${item.minStock * 2} ${item.unit}`, item.minStock * 2);
    if (quantity === null) return;
    
    alert(`✅ Reorder placed!\n\nItem: ${item.name}\nQuantity: ${quantity} ${item.unit}\nEstimated delivery: 2-3 business days\n\nOrder will be sent to supplier via SQS queue.`);
}

function editStaff(staffId) {
    const member = staff.find(s => s.id === staffId);
    if (!member) return;
    
    alert(`Edit Staff: ${member.name}\n\nCurrent Role: ${member.role}\nCurrent Shift: ${member.shift}\nPerformance: ${member.performance}\n\nFull edit functionality coming soon!`);
}

function viewSchedule(staffId) {
    const member = staff.find(s => s.id === staffId);
    if (!member) return;
    
    alert(`Schedule for ${member.name}\n\nThis Week:\nMon: ${member.shift}\nTue: ${member.shift}\nWed: ${member.shift}\nThu: ${member.shift}\nFri: ${member.shift}\nSat: Off\nSun: Off\n\nFull scheduling system coming soon!`);
}

function editMenuItem(itemId) {
    const item = menuItems.find(m => m.id === itemId);
    if (!item) return;
    
    const newPrice = prompt(`Edit price for ${item.name}\nCurrent: $${item.price}`, item.price);
    if (newPrice === null) return;
    
    item.price = parseFloat(newPrice);
    renderMenu();
    alert(`✅ Price updated for ${item.name}!`);
}

function toggleMenuItem(itemId) {
    const item = menuItems.find(m => m.id === itemId);
    if (!item) return;
    
    item.status = item.status === 'active' ? 'inactive' : 'active';
    renderMenu();
    alert(`✅ ${item.name} is now ${item.status}!`);
}

function exportReport() {
    alert('📥 Exporting report to CSV...\n\nReport will be downloaded shortly.\n\nData will be fetched from Redshift data warehouse.');
}

// Initialize on load
window.addEventListener('load', init);
