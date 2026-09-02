// MiBar Official Website Interactive Controller

document.addEventListener('DOMContentLoaded', () => {
  // --- Theme Management ---
  const themeToggleBtn = document.getElementById('themeToggleBtn');
  const themeMeta = document.querySelector('meta[name="theme-color"]');

  function applyTheme(theme) {
    if (theme === 'light') {
      document.documentElement.classList.add('light');
      document.documentElement.classList.remove('dark');
      if (themeMeta) themeMeta.setAttribute('content', '#f4f6fb');
    } else {
      document.documentElement.classList.add('dark');
      document.documentElement.classList.remove('light');
      if (themeMeta) themeMeta.setAttribute('content', '#090d16');
    }
  }

  // Toggle button click
  if (themeToggleBtn) {
    themeToggleBtn.addEventListener('click', () => {
      const isLight = document.documentElement.classList.contains('light');
      const nextTheme = isLight ? 'dark' : 'light';
      applyTheme(nextTheme);
      localStorage.setItem('mibar-theme', nextTheme);
      updateLightingSimulation();
    });
  }

  // Listen for system theme change if no explicit preference saved
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
    if (!localStorage.getItem('mibar-theme')) {
      applyTheme(e.matches ? 'dark' : 'light');
      updateLightingSimulation();
    }
  });

  // --- State ---
  const state = {
    power: true,
    brightness: 80,
    temperature: 4000 // 2700K to 6500K
  };

  // DOM Elements
  const powerToggle = document.getElementById('demoPowerToggle');
  const brightnessSlider = document.getElementById('demoBrightnessSlider');
  const brightnessFill = document.getElementById('brightnessFill');
  const brightnessLabel = document.getElementById('brightnessValueLabel');
  
  const tempSlider = document.getElementById('demoTempSlider');
  const tempLabel = document.getElementById('tempValueLabel');
  
  const lampTube = document.getElementById('virtualLampTube');
  const lightCone = document.getElementById('virtualLightCone');
  const lampStatus = document.getElementById('lampStatusDisplay');
  const ambientGlow = document.getElementById('ambientLightGlow');
  const controlsContainer = document.getElementById('controlsContainer');
  const presetButtons = document.querySelectorAll('.preset-btn');
  const mainHeader = document.getElementById('mainHeader');

  // Convert Kelvin (2700 - 6500) to RGB Color
  function kelvinToRGB(kelvin) {
    const temp = kelvin / 100;
    let red, green, blue;

    if (temp <= 66) {
      red = 255;
      green = Math.min(255, Math.max(0, 99.4708025861 * Math.log(temp) - 161.1195681661));
      if (temp <= 19) {
        blue = 0;
      } else {
        blue = Math.min(255, Math.max(0, 138.5177312231 * Math.log(temp - 10) - 305.0447927307));
      }
    } else {
      red = Math.min(255, Math.max(0, 329.698727446 * Math.pow(temp - 60, -0.1332047592)));
      green = Math.min(255, Math.max(0, 288.1221695283 * Math.pow(temp - 60, -0.0755148492)));
      blue = 255;
    }

    return {
      r: Math.round(red),
      g: Math.round(green),
      b: Math.round(blue)
    };
  }

  // Update Visual Lighting Simulation
  function updateLightingSimulation() {
    if (!state.power) {
      lampTube.style.backgroundColor = '#333333';
      lampTube.style.boxShadow = 'none';
      lightCone.style.opacity = '0';
      lampStatus.textContent = '挂灯已关闭';
      lampStatus.className = 'text-sm font-semibold text-slate-500 tracking-wide';
      brightnessFill.style.opacity = '0.3';
      return;
    }

    brightnessFill.style.opacity = '1';
    const rgb = kelvinToRGB(state.temperature);
    const colorStr = `rgb(${rgb.r}, ${rgb.g}, ${rgb.b})`;
    const intensity = state.brightness / 100;

    // Tube Glow
    lampTube.style.backgroundColor = colorStr;
    lampTube.style.boxShadow = `0 4px ${15 + intensity * 25}px rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${0.4 + intensity * 0.5})`;

    // Light Cone onto monitor & desk
    lightCone.style.opacity = `${0.2 + intensity * 0.8}`;
    lightCone.style.background = `radial-gradient(ellipse at top, rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${0.5 * intensity}) 0%, rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${0.15 * intensity}) 50%, transparent 80%)`;

    // Ambient page glow tint
    if (ambientGlow) {
      const isLight = document.documentElement.classList.contains('light');
      const glowAlpha = isLight ? 0.16 : 0.28;
      ambientGlow.style.background = `radial-gradient(circle, rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${glowAlpha * intensity}) 0%, transparent 70%)`;
    }

    lampStatus.textContent = `已开启 · ${state.brightness}% 亮度 · ${state.temperature}K`;
    lampStatus.className = 'text-sm font-semibold text-white tracking-wide';
  }

  // Power Switch Event
  powerToggle.addEventListener('click', () => {
    state.power = !state.power;
    powerToggle.classList.toggle('active', state.power);
    updateLightingSimulation();
  });

  // Brightness Slider Event
  brightnessSlider.addEventListener('input', (e) => {
    state.brightness = parseInt(e.target.value, 10);
    brightnessLabel.textContent = `${state.brightness}%`;
    brightnessFill.style.width = `${state.brightness}%`;
    if (!state.power) {
      state.power = true;
      powerToggle.classList.add('active');
    }
    clearActivePreset();
    updateLightingSimulation();
  });

  // Temperature Slider Event
  tempSlider.addEventListener('input', (e) => {
    state.temperature = parseInt(e.target.value, 10);
    tempLabel.textContent = `${state.temperature} K`;
    if (!state.power) {
      state.power = true;
      powerToggle.classList.add('active');
    }
    clearActivePreset();
    updateLightingSimulation();
  });

  // Preset Buttons Event
  presetButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const b = parseInt(btn.dataset.brightness, 10);
      const t = parseInt(btn.dataset.temp, 10);

      state.brightness = b;
      state.temperature = t;
      state.power = true;
      powerToggle.classList.add('active');

      brightnessSlider.value = b;
      brightnessLabel.textContent = `${b}%`;
      brightnessFill.style.width = `${b}%`;

      tempSlider.value = t;
      tempLabel.textContent = `${t} K`;

      presetButtons.forEach(p => p.classList.remove('active'));
      btn.classList.add('active');

      updateLightingSimulation();
    });
  });

  function clearActivePreset() {
    presetButtons.forEach(p => p.classList.remove('active'));
  }

  // FAQ Accordion
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const trigger = item.querySelector('.faq-trigger');
    trigger.addEventListener('click', () => {
      const isOpen = item.classList.contains('open');
      faqItems.forEach(i => i.classList.remove('open'));
      if (!isOpen) {
        item.classList.add('open');
      }
    });
  });

  // Scroll Header Shadow
  window.addEventListener('scroll', () => {
    if (window.scrollY > 20) {
      mainHeader.classList.add('shadow-lg');
    } else {
      mainHeader.classList.remove('shadow-lg');
    }
  });

  // Initial Run
  updateLightingSimulation();
});
