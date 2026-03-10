let resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'dnj_bossmenu'; 
let financeChart = null;
let allActivities = []; 
let currentEmployees = [];
let employeeFilter = 'all';
let employeeSearchTerm = '';
let bonusModal = null;
let toastStackEl = null;

document.addEventListener('DOMContentLoaded', () => {
  localStorage.removeItem('boss-menu-accent');
  document.documentElement.style.setProperty('--accent-color', '#a855f7');
  
  const savedTheme = localStorage.getItem('boss-menu-theme');
  if (savedTheme === 'light') {
    document.body.classList.add('light-theme');
  }

  const viewAllBtn = document.getElementById('view-all-activities-btn');
  if (viewAllBtn) {
    viewAllBtn.addEventListener('click', openActivityModal);
  }

  const refreshBtn = document.getElementById('refresh-employees-btn');
  if (refreshBtn) {
      refreshBtn.addEventListener('click', () => {
          fetch(`https://${resourceName}/refreshEmployees`, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({})
          }).catch(() => {});
          
          refreshBtn.querySelector('i').classList.add('fa-spin');
          setTimeout(() => {
              refreshBtn.querySelector('i').classList.remove('fa-spin');
          }, 1000);
      });
  }

  // Tlačítko pro uložení mezd
  const saveSalariesBtn = document.getElementById("save-salaries-btn");
  if (saveSalariesBtn) {
    saveSalariesBtn.addEventListener("click", () => {
      const salaryData = {};
      document.querySelectorAll(".salary-input").forEach(input => {
        const grade = input.getAttribute("data-grade");
        const salary = parseInt(input.value);
        if (grade !== null && !isNaN(salary)) {
            salaryData[grade] = { salary: salary };
        }
      });

      fetch(`https://${resourceName}/updateSalaries`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ salaryData: salaryData })
      }).catch(() => {});
      
      // Vizuální efekt kliknutí
      saveSalariesBtn.style.transform = "scale(0.95)";
      setTimeout(() => { saveSalariesBtn.style.transform = "scale(1)"; }, 100);
    });
  }

  const searchInput = document.getElementById('employee-search');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      employeeSearchTerm = e.target.value.toLowerCase();
      renderEmployeeList();
    });
  }

  document.querySelectorAll('.filter-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.filter-btn').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      employeeFilter = btn.getAttribute('data-filter') || 'all';
      renderEmployeeList();
    });
  });

  document.querySelectorAll('.quick-amount-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const value = Number(btn.getAttribute('data-amount')) || 0;
      const input = document.getElementById('amount-input');
      if (!input) return;
      input.value = value;
      input.dispatchEvent(new Event('input'));
    });
  });

  const announcementInput = document.getElementById('announcement-input');
  const announcementCounter = document.getElementById('announcement-counter');
  if (announcementInput && announcementCounter) {
    announcementCounter.innerText = announcementInput.value.length;
    announcementInput.addEventListener('input', () => {
      announcementCounter.innerText = announcementInput.value.length;
    });
  }

  const announcementBtn = document.getElementById('announcement-btn');
  if (announcementBtn && announcementInput) {
    announcementBtn.addEventListener('click', () => {
      const message = announcementInput.value.trim();
      if (message.length < 5) {
        announcementInput.style.borderColor = '#ef4444';
        setTimeout(() => {
          announcementInput.style.borderColor = '#262626';
        }, 800);
        return;
      }
      fetch(`https://${resourceName}/sendAnnouncement`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ message })
      }).catch(() => {});

      announcementInput.value = '';
      if (announcementCounter) {
        announcementCounter.innerText = '0';
      }
    });
  }
});

window.addEventListener("message", (event) => {
  const data = event.data;

  if (data.action === "showMenu") {
    if (data.resourceName) {
      resourceName = data.resourceName;
    }
    
    document.getElementById("main-container").classList.add("active");
    
    const jobTitle = document.getElementById("job-title");
    if (jobTitle) jobTitle.innerText = data.jobLabel;
    
    const companyName = document.getElementById("company-name");
    if (companyName) companyName.innerText = data.jobLabel;
    
    if (data.activities) {
        allActivities = data.activities;
    }

    updateEmployeeList(data.employees);
    updateSocietyMoney(data.money);
    updateDashboardStats(data.employees, data.money, data.weeklyStats);
    updateActivityList(data.activities);
    updateFinanceChart(data.chartData);
    
    if (data.grades && data.grades.length > 0) {
      displayGrades(data.grades);
    }
  } else if (data.action === "hideMenu") {
    document.getElementById("main-container").classList.remove("active");
  } else if (data.action === "updateData") {
    
    if (data.activities) {
        allActivities = data.activities;
    }

    updateEmployeeList(data.employees);
    updateSocietyMoney(data.money);
    updateDashboardStats(data.employees, data.money, data.weeklyStats);
    updateActivityList(data.activities);
    updateFinanceChart(data.chartData);
    
    if (data.grades && data.grades.length > 0) {
      displayGrades(data.grades);
    }
  } else if (data.action === "cyBossToast") {
    showBossToast(data.data || {});
  }
});

// Chybějící funkce displayGrades
function displayGrades(grades) {
  const container = document.getElementById("grades-list");
  if (!container) return;
  container.innerHTML = "";

  grades.forEach((grade) => {
    const div = document.createElement("div");
    div.className = "grade-card";
    div.innerHTML = `
      <div class="grade-row">
        <div class="grade-pill">${grade.grade}</div>
        <div class="grade-info">
          <span class="grade-label">${grade.label}</span>
          <span class="grade-meta">Mzda</span>
        </div>
        <div class="grade-input-inline">
          <i class="fas fa-money-bill"></i>
          <input type="number" class="salary-input" data-grade="${grade.grade}" value="${grade.salary}" min="0">
          <div class="salary-stepper">
            <button type="button" class="salary-step salary-up" aria-label="Zvýšit mzdu"></button>
            <button type="button" class="salary-step salary-down" aria-label="Snížit mzdu"></button>
          </div>
        </div>
      </div>
    `;
    container.appendChild(div);
  });

  attachSalarySteppers();
}

function attachSalarySteppers() {
  document.querySelectorAll('.salary-step').forEach((button) => {
    button.addEventListener('click', () => {
      const inline = button.closest('.grade-input-inline');
      const input = inline ? inline.querySelector('.salary-input') : null;
      if (!input) return;

      const current = Number.parseInt(input.value, 10) || 0;
      const delta = button.classList.contains('salary-up') ? 1 : -1;
      const nextValue = Math.max(0, current + delta);
      input.value = nextValue;
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
  });
}

function ensureToastStack() {
  if (!toastStackEl) {
    toastStackEl = document.createElement('div');
    toastStackEl.id = 'boss-toast-stack';
    document.body.appendChild(toastStackEl);
  }
  return toastStackEl;
}

function sanitizeText(text) {
  if (!text) return '';
  return text.replace(/[&<>"']/g, (char) => {
    const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
    return map[char] || char;
  });
}

function showBossToast(payload) {
  const container = ensureToastStack();
  const toast = document.createElement('div');
  toast.className = 'boss-toast';

  const title = sanitizeText(payload.title || 'Oznámení');
  const message = sanitizeText(payload.message || '');
  const sender = sanitizeText(payload.sender || '');

  toast.innerHTML = `
    <div class="boss-toast-ring">
      <i class="fas fa-bullhorn"></i>
    </div>
    <div class="boss-toast-body">
      <div class="boss-toast-title">${title}</div>
      <div class="boss-toast-message">${message}</div>
      ${sender ? `<div class="boss-toast-sender">${sender}</div>` : ''}
    </div>
  `;

  container.appendChild(toast);
  requestAnimationFrame(() => toast.classList.add('show'));

  setTimeout(() => {
    toast.classList.remove('show');
    toast.classList.add('hide');
    toast.addEventListener('transitionend', () => toast.remove(), { once: true });
  }, 5500);
}

function updateFinanceChart(chartData) {
  if (!chartData || !chartData.labels) return;
  
  const ctx = document.getElementById('financeChart');
  if (!ctx) return;
  
  if (financeChart) {
    financeChart.destroy();
  }
  
  financeChart = new Chart(ctx, {
    type: 'line',
    data: {
      labels: chartData.labels,
      datasets: [
        {
          label: 'Vklady',
          data: chartData.deposits,
          borderColor: '#22c55e',
          backgroundColor: 'rgba(34, 197, 94, 0.1)',
          borderWidth: 2,
          tension: 0.4,
          fill: true,
          pointBackgroundColor: '#22c55e',
          pointBorderColor: '#22c55e',
          pointRadius: 4,
          pointHoverRadius: 6
        },
        {
          label: 'Výběry',
          data: chartData.withdrawals,
          borderColor: '#eab308',
          backgroundColor: 'rgba(234, 179, 8, 0.1)',
          borderWidth: 2,
          tension: 0.4,
          fill: true,
          pointBackgroundColor: '#eab308',
          pointBorderColor: '#eab308',
          pointRadius: 4,
          pointHoverRadius: 6
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          display: true,
          position: 'top',
          labels: {
            color: '#e5e5e5',
            font: { family: 'Inter', size: 12 },
            padding: 15,
            usePointStyle: true,
            pointStyle: 'circle'
          }
        },
        tooltip: {
          backgroundColor: '#1a1a1a',
          titleColor: '#e5e5e5',
          bodyColor: '#e5e5e5',
          borderColor: '#262626',
          borderWidth: 1,
          padding: 12,
          displayColors: true,
          callbacks: {
            label: function(context) {
              let label = context.dataset.label || '';
              if (label) label += ': ';
              label += new Intl.NumberFormat('cs-CZ', {
                style: 'currency', currency: 'USD', minimumFractionDigits: 0, maximumFractionDigits: 0
              }).format(context.parsed.y);
              return label;
            }
          }
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          grid: { color: '#1a1a1a', drawBorder: false },
          ticks: {
            color: '#666666',
            font: { family: 'Inter', size: 11 },
            callback: function(value) { return '$' + value.toLocaleString('cs-CZ'); }
          }
        },
        x: {
          grid: { display: false, drawBorder: false },
          ticks: { color: '#666666', font: { family: 'Inter', size: 11 } }
        }
      },
      interaction: { intersect: false, mode: 'index' }
    }
  });
}

function updateActivityList(activities) {
  const activityList = document.getElementById("activity-list");
  if (!activityList) return;
  activityList.innerHTML = "";
  
  if (!activities || activities.length === 0) {
    activityList.innerHTML = `
      <div class="empty-state" style="padding: 20px;">
        <i class="fas fa-history"></i>
        <p>Žádná aktivita</p>
      </div>
    `;
    return;
  }
  
  const recentActivities = activities.slice(0, 5);
  
  recentActivities.forEach((activity, index) => {
    const activityItem = document.createElement("div");
    activityItem.className = "activity-item";
    activityItem.style.animationDelay = `${index * 0.05}s`;
    activityItem.style.opacity = "0";
    activityItem.style.animation = "slideIn 0.2s ease forwards";
    
    let iconClass = "fas fa-circle-info";
    let iconType = "success";
    
    if (activity.type === "success" || activity.type === "deposit") {
      iconClass = "fas fa-arrow-down";
      iconType = "success";
    } else if (activity.type === "warning" || activity.type === "withdraw") {
      iconClass = "fas fa-arrow-up";
      iconType = "warning";
    } else if (activity.type === "danger" || activity.type === "fire") {
      iconClass = "fas fa-times";
      iconType = "danger";
    } else if (activity.type === "hire") {
      iconClass = "fas fa-user-plus";
      iconType = "success";
    } else if (activity.type === "info" || activity.type === "announcement") {
      iconClass = "fas fa-bullhorn";
      iconType = "info";
    }
    
    activityItem.innerHTML = `
      <div class="activity-icon ${iconType}">
        <i class="${iconClass}"></i>
      </div>
      <div class="activity-content">
        <span class="activity-text">${activity.text || activity.message || "Akce"}</span>
        <span class="activity-time">${activity.time || ""}</span>
      </div>
    `;
    
    activityList.appendChild(activityItem);
  });
}

function updateEmployeeList(employees) {
  currentEmployees = Array.isArray(employees) ? employees : [];
  renderEmployeeList();
}

function renderEmployeeList() {
  const list = document.getElementById("employee-list");
  if (!list) return;
  list.innerHTML = "";

  if (!currentEmployees || currentEmployees.length === 0) {
    list.innerHTML = `
      <div class="empty-state">
        <i class="fas fa-users-slash"></i>
        <p>Žádní zaměstnanci</p>
      </div>
    `;
    return;
  }

  const filtered = currentEmployees.filter((emp) => {
    if (employeeFilter === 'online' && !emp.isOnline) return false;
    if (employeeFilter === 'offline' && emp.isOnline) return false;
    if (employeeSearchTerm) {
      const haystack = `${emp.name || ''} ${emp.grade_label || ''}`.toLowerCase();
      if (!haystack.includes(employeeSearchTerm)) return false;
    }
    return true;
  });

  if (filtered.length === 0) {
    list.innerHTML = `
      <div class="empty-state">
        <i class="fas fa-magnifying-glass"></i>
        <p>Nenalezen žádný zaměstnanec</p>
      </div>
    `;
    return;
  }

  filtered.forEach((emp, index) => {
    const li = document.createElement("li");
    li.style.animationDelay = `${index * 0.05}s`;
    
    const salary = new Intl.NumberFormat("cs-CZ", {
      style: "currency", currency: "USD", minimumFractionDigits: 0, maximumFractionDigits: 0,
    }).format(emp.salary || 0);
    
    const bonus = new Intl.NumberFormat("cs-CZ", {
      style: "currency", currency: "USD", minimumFractionDigits: 0, maximumFractionDigits: 0,
    }).format(emp.bonus || 0);
    
    const statusClass = emp.isOnline ? 'status-online' : 'status-offline';
    const statusText = emp.isOnline ? 'Online' : 'Offline';
    const safeAttrName = (emp.name || 'Zaměstnanec').replace(/"/g, '&quot;');

    li.innerHTML = `
      <div class="employee-info">
        <div style="display: flex; justify-content: space-between; align-items: center;">
            <span class="employee-name">${emp.name}</span>
            <span class="status-badge ${statusClass}"><i class="fas fa-circle"></i> ${statusText}</span>
        </div>
        <span class="employee-grade">${emp.grade_label}</span>
        <div class="employee-salary-info">
          <span class="salary-badge">
            <i class="fas fa-money-bill-wave"></i> Výplata: ${salary}
          </span>
          <span class="bonus-badge">
            <i class="fas fa-gift"></i> Bonus: ${bonus}
          </span>
        </div>
      </div>
      <div class="employee-buttons">
        <button class="bonus-btn" data-id="${emp.identifier}" data-name="${safeAttrName}" title="Vyplatit bonus">
          <i class="fas fa-gift"></i>
        </button>
        <button class="promote-btn" data-id="${emp.identifier}" title="Povýšit">
          <i class="fas fa-arrow-up"></i>
        </button>
        <button class="demote-btn" data-id="${emp.identifier}" title="Degradovat">
          <i class="fas fa-arrow-down"></i>
        </button>
        <button class="fire-btn" data-id="${emp.identifier}" title="Vyhodit">
          <i class="fas fa-user-times"></i>
        </button>
      </div>
    `;
    list.appendChild(li);
  });

  attachEmployeeActionListeners();
}

function updateSocietyMoney(amount) {
  const moneyElement = document.getElementById("society-money");
  const formattedAmount = new Intl.NumberFormat("cs-CZ", {
    style: "currency", currency: "USD", minimumFractionDigits: 0, maximumFractionDigits: 0,
  }).format(amount || 0);

  moneyElement.innerText = formattedAmount;
  document.getElementById("stat-money").innerText = formattedAmount;

  moneyElement.style.transform = "scale(1.05)";
  setTimeout(() => {
    moneyElement.style.transform = "scale(1)";
  }, 200);
}

function closeMenu() {
  fetch(`https://${resourceName}/close`, { method: "POST" }).catch(() => {});
}

document.getElementById("close-btn").addEventListener("click", closeMenu);

document.getElementById("deposit-btn").addEventListener("click", () => {
  const input = document.getElementById("amount-input");
  const amount = Number.parseInt(input.value);

  if (amount && amount > 0) {
    fetch(`https://${resourceName}/deposit`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify({ amount: amount }),
    }).catch(() => {});
    
    input.value = "";
    const btn = document.getElementById("deposit-btn");
    btn.style.transform = "scale(0.95)";
    setTimeout(() => { btn.style.transform = "scale(1)" }, 100);
  } else {
    input.style.borderColor = "#ef4444";
    setTimeout(() => { input.style.borderColor = "#262626" }, 1000);
  }
});

document.getElementById("withdraw-btn").addEventListener("click", () => {
  const input = document.getElementById("amount-input");
  const amount = Number.parseInt(input.value);

  if (amount && amount > 0) {
    fetch(`https://${resourceName}/withdraw`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify({ amount: amount }),
    }).catch(() => {});
    
    input.value = "";
    const btn = document.getElementById("withdraw-btn");
    btn.style.transform = "scale(0.95)";
    setTimeout(() => { btn.style.transform = "scale(1)" }, 100);
  } else {
    input.style.borderColor = "#ef4444";
    setTimeout(() => { input.style.borderColor = "#262626" }, 1000);
  }
});

document.getElementById("hire-btn").addEventListener("click", () => {
  if (!resourceName) {
    console.error("Resource name not set!");
    return;
  }
  
  fetch(`https://${resourceName}/openHireMenu`, { 
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({})
  }).catch((err) => console.error("Hire menu error:", err));
});

function attachEmployeeActionListeners() {
  document.querySelectorAll(".bonus-btn").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      const identifier = e.currentTarget.getAttribute("data-id");
      const name = e.currentTarget.getAttribute("data-name");
      openBonusModal(identifier, name);
    });
  });

  document.querySelectorAll(".fire-btn").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      const identifier = e.currentTarget.getAttribute("data-id");
      fetch(`https://${resourceName}/fire`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify({ identifier: identifier }),
      }).catch(() => {});
    });
  });

  document.querySelectorAll(".promote-btn").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      const identifier = e.currentTarget.getAttribute("data-id");
      fetch(`https://${resourceName}/promote`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify({ identifier: identifier }),
      }).catch(() => {});
    });
  });

  document.querySelectorAll(".demote-btn").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      const identifier = e.currentTarget.getAttribute("data-id");
      fetch(`https://${resourceName}/demote`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify({ identifier: identifier }),
      }).catch(() => {});
    });
  });
}

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    closeMenu();
  }
});

document.getElementById("amount-input").addEventListener("input", (e) => {
  const value = e.target.value;
  if (value && Number.parseInt(value) > 0) {
    e.target.style.borderColor = "#a855f7";
  } else {
    e.target.style.borderColor = "#262626";
  }
});

document.getElementById("amount-input").addEventListener("keypress", (e) => {
  if (!/[0-9]/.test(e.key)) {
    e.preventDefault();
  }
});

document.querySelectorAll(".nav-item").forEach((item) => {
  item.addEventListener("click", (e) => {
    const section = e.currentTarget.getAttribute("data-section");
    document.querySelectorAll(".nav-item").forEach((nav) => nav.classList.remove("active"));
    e.currentTarget.classList.add("active");
    document.querySelectorAll(".section-view").forEach((view) => view.classList.remove("active"));
    document.getElementById(`${section}-section`).classList.add("active");
  });
});

document.querySelectorAll(".quick-action-btn").forEach((btn) => {
  btn.addEventListener("click", (e) => {
    const section = e.currentTarget.getAttribute("data-section");
    document.querySelectorAll(".nav-item").forEach((nav) => nav.classList.remove("active"));
    const navItem = document.querySelector(`.nav-item[data-section="${section}"]`);
    if (navItem) navItem.classList.add("active");
    document.querySelectorAll(".section-view").forEach((view) => view.classList.remove("active"));
    document.getElementById(`${section}-section`).classList.add("active");

    const anchor = e.currentTarget.getAttribute("data-anchor");
    if (anchor) {
      setTimeout(() => {
        const target = document.getElementById(anchor);
        if (target) {
          target.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      }, 50);
    }
  });
});



function updateDashboardStats(employees, money, weeklyStats) {
  const totalEmployees = employees ? employees.length : 0;
  const onlineEmployees = employees ? employees.filter(emp => emp.isOnline).length : 0;
  const payrollSum = employees ? employees.reduce((sum, emp) => sum + (emp.salary || 0), 0) : 0;

  document.getElementById("stat-employees").innerText = totalEmployees;
  const statOnline = document.getElementById("stat-online");
  if (statOnline) {
    statOnline.innerText = onlineEmployees;
  }

  const formatter = new Intl.NumberFormat("cs-CZ", {
    style: "currency", currency: "USD", minimumFractionDigits: 0, maximumFractionDigits: 0,
  });

  document.getElementById("stat-money").innerText = formatter.format(money || 0);

  const payrollElement = document.getElementById("stat-payroll");
  if (payrollElement) {
    payrollElement.innerText = formatter.format(payrollSum);
  }

  if (weeklyStats) {
    document.getElementById("stat-deposits").innerText = formatter.format(weeklyStats.deposits || 0);
    document.getElementById("stat-withdrawals").innerText = formatter.format(weeklyStats.withdrawals || 0);
  } else {
    document.getElementById("stat-deposits").innerText = "$0";
    document.getElementById("stat-withdrawals").innerText = "$0";
  }
}

let availableGrades = [];

function closeHireModal() {
  const modal = document.getElementById('hire-modal');
  if (modal) modal.classList.remove('active');
}

window.hirePlayer = function(playerId, grade) {
  fetch(`https://${resourceName}/hirePlayer`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({ targetId: playerId, grade: parseInt(grade) }),
  }).catch(() => {});
  closeHireModal();
};

window.addEventListener('message', (event) => {
  if (event.data.action === 'showHireMenu') {
    availableGrades = event.data.grades;
    displayHireMenu(event.data.players, event.data.grades);
  }
});

function displayHireMenu(players, grades) {
  let modal = document.getElementById('hire-modal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'hire-modal';
    modal.className = 'modal';
    modal.innerHTML = `
      <div class="modal-content">
        <div class="modal-header">
          <h3><i class="fas fa-user-plus"></i> Zaměstnat občana</h3>
          <button class="modal-close">
            <i class="fas fa-times"></i>
          </button>
        </div>
        <div class="modal-body" id="hire-modal-body"></div>
      </div>
    `;
    document.body.appendChild(modal);
    modal.querySelector('.modal-close').addEventListener('click', closeHireModal);
  }
  
  const modalBody = document.getElementById('hire-modal-body');
  modalBody.innerHTML = '';
  
  if (!players || players.length === 0) {
    modalBody.innerHTML = `
      <div class="modal-empty">
        <i class="fas fa-users-slash"></i>
        <p>V blízkosti není nikdo</p>
      </div>
    `;
  } else {
    players.forEach(player => {
      const playerItem = document.createElement('div');
      playerItem.className = 'player-item';
      
      playerItem.innerHTML = `
        <div class="player-info">
          <span class="player-name">${player.name}</span>
          <div class="player-details">
            <span><i class="fas fa-id-card"></i> ID: ${player.id}</span>
            <span><i class="fas fa-location-dot"></i> ${player.distance}m</span>
          </div>
        </div>
        <div class="grade-selection">
          <div class="grade-selection-label">Vyberte hodnost</div>
          <div class="grade-options" id="grade-options-${player.id}"></div>
        </div>
        <button class="player-hire-btn" id="hire-btn-${player.id}" disabled>
          <i class="fas fa-check"></i> Zaměstnat
        </button>
      `;
      
      modalBody.appendChild(playerItem);
      
      const gradeOptionsContainer = document.getElementById(`grade-options-${player.id}`);
      let selectedGrade = null;
      
      grades.forEach(grade => {
        const gradeOption = document.createElement('div');
        gradeOption.className = 'grade-option';
        gradeOption.innerHTML = `
          <span class="grade-option-label">${grade.label}</span>
          <span class="grade-option-level">Grade ${grade.grade}</span>
        `;
        
        gradeOption.addEventListener('click', () => {
          document.querySelectorAll(`#grade-options-${player.id} .grade-option`).forEach(opt => {
            opt.classList.remove('selected');
          });
          gradeOption.classList.add('selected');
          selectedGrade = grade.grade;
          document.getElementById(`hire-btn-${player.id}`).disabled = false;
        });
        
        gradeOptionsContainer.appendChild(gradeOption);
      });
      
      document.getElementById(`hire-btn-${player.id}`).addEventListener('click', function() {
        if (selectedGrade !== null) {
          hirePlayer(player.id, selectedGrade);
        }
      });
    });
  }
  modal.classList.add('active');
}

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    const hireModal = document.getElementById('hire-modal');
    if (hireModal && hireModal.classList.contains('active')) closeHireModal();
    if (bonusModal && bonusModal.classList.contains('active')) closeBonusModal();
  }
});


function closeActivityModal() {
  const modal = document.getElementById('activity-modal');
  if (modal) modal.classList.remove('active');
}

function openActivityModal() {
  let modal = document.getElementById('activity-modal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'activity-modal';
    modal.className = 'activity-modal';
    modal.innerHTML = `
      <div class="activity-modal-content">
        <div class="activity-modal-header">
          <h3><i class="fas fa-history"></i> Všechny aktivity</h3>
          <button class="activity-modal-close">
            <i class="fas fa-times"></i>
          </button>
        </div>
        <div class="activity-modal-body">
          <div class="activity-list" id="activity-modal-list"></div>
        </div>
      </div>
    `;
    document.body.appendChild(modal);
    modal.querySelector('.activity-modal-close').addEventListener('click', closeActivityModal);
  }
  
  const modalList = document.getElementById('activity-modal-list');
  modalList.innerHTML = '';
  
  if (!allActivities || allActivities.length === 0) {
    modalList.innerHTML = `
      <div class="empty-state" style="padding: 20px;">
        <i class="fas fa-history"></i>
        <p>Žádná aktivita</p>
      </div>
    `;
  } else {
    allActivities.forEach((activity, index) => {
      const activityItem = document.createElement("div");
      activityItem.className = "activity-item";
      activityItem.style.animationDelay = `${index * 0.02}s`;
      activityItem.style.opacity = "0";
      activityItem.style.animation = "slideIn 0.2s ease forwards";
      
      let iconClass = "fas fa-circle-info";
      let iconType = "success";
      
      if (activity.type === "success" || activity.type === "deposit") {
        iconClass = "fas fa-arrow-down";
        iconType = "success";
      } else if (activity.type === "warning" || activity.type === "withdraw") {
        iconClass = "fas fa-arrow-up";
        iconType = "warning";
      } else if (activity.type === "danger" || activity.type === "fire") {
        iconClass = "fas fa-times";
        iconType = "danger";
      } else if (activity.type === "hire") {
        iconClass = "fas fa-user-plus";
        iconType = "success";
      } else if (activity.type === "info" || activity.type === "announcement") {
        iconClass = "fas fa-bullhorn";
        iconType = "info";
      }
      
      activityItem.innerHTML = `
        <div class="activity-icon ${iconType}">
          <i class="${iconClass}"></i>
        </div>
        <div class="activity-content">
          <span class="activity-text">${activity.text || activity.message || "Akce"}</span>
          <span class="activity-time">${activity.time || ""}</span>
        </div>
      `;
      modalList.appendChild(activityItem);
    });
  }
  modal.classList.add('active');
}

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    const activityModal = document.getElementById('activity-modal');
    if (activityModal && activityModal.classList.contains('active')) closeActivityModal();
  }
});

function ensureBonusModal() {
  if (bonusModal) return bonusModal;
  bonusModal = document.createElement('div');
  bonusModal.id = 'bonus-modal';
  bonusModal.className = 'modal';
  bonusModal.innerHTML = `
    <div class="modal-content">
      <div class="modal-header">
        <h3><i class="fas fa-gift"></i> Vyplatit bonus</h3>
        <button class="modal-close">
          <i class="fas fa-times"></i>
        </button>
      </div>
      <div class="modal-body">
        <p style="margin-bottom: 16px;">Jednorázová odměna pro <strong id="bonus-employee-name"></strong></p>
        <div class="input-group-large">
          <label>Výše bonusu</label>
          <div class="input-wrapper">
            <i class="fas fa-coins"></i>
            <input type="number" id="bonus-amount-input" placeholder="Např. 5000">
          </div>
        </div>
        <button id="bonus-confirm-btn" class="btn btn-success btn-full" style="margin-top: 16px;">
          <i class="fas fa-check"></i>
          <span>Vyplatit bonus</span>
        </button>
      </div>
    </div>
  `;
  document.body.appendChild(bonusModal);
  bonusModal.querySelector('.modal-close').addEventListener('click', closeBonusModal);
  bonusModal.querySelector('#bonus-confirm-btn').addEventListener('click', submitBonus);
  return bonusModal;
}

function openBonusModal(identifier, name) {
  if (!identifier) return;
  const modal = ensureBonusModal();
  modal.dataset.identifier = identifier;
  const nameLabel = document.getElementById('bonus-employee-name');
  if (nameLabel) {
    nameLabel.innerText = name || 'Zaměstnanec';
  }
  const input = document.getElementById('bonus-amount-input');
  if (input) {
    input.value = '';
    setTimeout(() => input.focus(), 50);
  }
  modal.classList.add('active');
}

function closeBonusModal() {
  if (bonusModal) {
    bonusModal.classList.remove('active');
    bonusModal.dataset.identifier = '';
  }
}

function submitBonus() {
  if (!bonusModal) return;
  const identifier = bonusModal.dataset.identifier;
  const input = document.getElementById('bonus-amount-input');
  if (!input) return;
  const amount = Number.parseInt(input.value);

  if (!identifier || !amount || amount <= 0) {
    input.style.borderColor = '#ef4444';
    setTimeout(() => { input.style.borderColor = '#262626'; }, 800);
    return;
  }

  fetch(`https://${resourceName}/payBonus`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({ identifier, amount })
  }).catch(() => {});

  closeBonusModal();
}
