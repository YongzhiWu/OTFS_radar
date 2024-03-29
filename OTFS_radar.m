clc, clear

% Waveform parameters
M = 256; % subcarrier number
N = 16; % symbol number
modSize = 4; % modulation size
deltaf = 15e3 * 2^4; % subcarrier spacing
T = 1 / deltaf; % symbol duration
cpSize = M / 4;
cpDuration = cpSize / M * T;

% Channel parameters
c0 = physconst('LightSpeed'); % light of speed
fc = 30e9; % carrier frequency
targetDistance = 30;
targetDelay = range2time(targetDistance, c0);
targetVelocity = 72 / 3.6;
targetDoppler = speed2dop(2 * targetVelocity, c0 / fc);
targetCoefficient = exp(1j * 2 * pi * rand());
SNRdB = -10;
maximumSensingRange = c0 * cpDuration / 2;

% OTFS ISAC transmitter
dataBits = randi([0 1], M * N, log2(modSize));
dataDe = bi2de(dataBits);
dataDe = reshape(dataDe, M, N);
data = qammod(dataDe, modSize, 'UnitAveragePower',true);
ddSignal = data;
tfSignal = ISFFT(ddSignal, M, N);
txFrame = ifft(tfSignal) * sqrt(M);
txSignal = reshape(txFrame, [], 1);

% Channel realization
alpha = targetCoefficient;
delay = targetDelay;
doppler = targetDoppler;
tfSignal = fft(reshape(txSignal, M, N)) / sqrt(M);
txSignal_delay = zeros(M * N, 1);
l_tau = ceil(delay / (T / M));
txSignal_delay(:, 1) = circshift(reshape(circshift(ifft(diag(exp(-1j * 2 * pi * (0:1:(M-1)) *  deltaf * delay)) * tfSignal ) * sqrt(M), - l_tau ), [], 1), l_tau);
dopplerEffect = exp(1j * 2 * pi * doppler .* (0:1:(M*N - 1))' * T / M);
rxSignal = repmat(alpha, M*N, 1) .* dopplerEffect .* txSignal_delay;
rxSignal = sum(rxSignal, 2);
rxSignal = awgn(rxSignal, SNRdB, 'measured');

% Sensing receiver
Ytf = WignerTransform(rxSignal, M, N);
Ydd = SFFT(Ytf, M, N);
Xdd = ddSignal;

% Two-phase sensing estimation algorithm
ydd = Ydd(:);
K = 60;
% phase I
delayList = (0:1:(M-1)) * T / M;
DopplerList = (-N/2:1:(N/2 - 1)) * deltaf / N;
profile = zeros(M, N);
for m = 1:length(delayList)
    for n = 1:length(DopplerList)
        ydd_p = OTFS_approximatedOutput(Xdd, T, delayList(m), DopplerList(n));
        profile(m, n) = abs(ydd_p' * ydd)^2;
    end
end
[~, index] = max(profile(:));
[mi, ni] = ind2sub(size(profile), index);
% phase II
phi = double( (sqrt(5) - 1) / 2);
a1 = mi - 2; b1 = mi;
a2 = ni - N/2 - 2; b2 = ni - N/2;
for k = 1:K
    I1 = b1 - a1; I2 = b2 - a2;
    x1 = a1 + (1 - phi) * I1; x2 = a1 + phi * I1;
    y1 = a2 + (1 - phi) * I2; y2 = a2 + phi * I2;
    ydd_11 = OTFS_output(Xdd, T, x1 * T / M, y1 * deltaf / N);
    ydd_12 = OTFS_output(Xdd, T, x1 * T / M, y2 * deltaf / N);
    ydd_21 = OTFS_output(Xdd, T, x2 * T / M, y1 * deltaf / N);
    ydd_22 = OTFS_output(Xdd, T, x2 * T / M, y2 * deltaf / N);
    f11 = abs(ydd_11' * ydd)^2;
    f12 = abs(ydd_12' * ydd)^2;
    f21 = abs(ydd_21' * ydd)^2;
    f22 = abs(ydd_22' * ydd)^2;
    [~, fmax] = max([f11, f12, f21, f22]);
    switch fmax
        case 1, b1 = x2; b2 = y2;
        case 2, b1 = x2; a2 = y1;
        case 3, a1 = x1; b2 = y2;
        case 4, a1 = x1; a2 = y1;
    end
end
estimatedDelay = (a1 + b1) / 2 * T / M;
estimatedDoppler = (a2 + b2) / 2 * deltaf / N;
estimatedRange = estimatedDelay * c0 / 2;
estimatedVelocity = estimatedDoppler * c0 / fc / 2;
Hp = OTFS_output(Xdd, T, estimatedDelay, estimatedDoppler);
estimatedAlpha = (Hp' * Hp) \ (Hp' * ydd);

% Display sensing estimation result
sensingResult = ['The estimated target range is ', num2str(estimatedRange), ' m.'];
sensingResult2 = ['The estimated target velocity is ', num2str(estimatedVelocity), ' m/s.'];
disp(sensingResult);
disp(sensingResult2);

% matlab functions
function tfSignal = ISFFT(ddSignal, M, N)
tfSignal = fft(ifft(ddSignal.').') * sqrt(N) / sqrt(M);
end

function tfSignal = WignerTransform(rxSignal, M, N)
tfSignal = reshape(rxSignal, M, N);
tfSignal = fft(tfSignal) / sqrt(M);
end

function ddSignal = SFFT(tfSignal, M, N)
ddSignal = ifft(fft(tfSignal.').') / sqrt(N) * sqrt(M);
end

function ydd = OTFS_output(Xdd, T, delay, Doppler)
[M, N] = size(Xdd);
lt = ceil(delay / (T / M));
deltaf = 1 / T;
Xtf = ISFFT(Xdd, M, N);
rt = exp(1j * 2 * pi * Doppler * (0:1:(M*N - 1))' * T / M) .* circshift(reshape(circshift(ifft(diag(exp(-1j * 2 * pi * (0:1:(M-1)) *  deltaf * delay)) * Xtf ) * sqrt(M), - lt ), [], 1), lt);
Rt = reshape(rt, M, N);
Ydd = fft(Rt.').' / sqrt(N);
ydd = Ydd(:);
end

function ydd = OTFS_approximatedOutput(Xdd, T, delay, Doppler)
[M, N] = size(Xdd);
lt = ceil(delay / (T / M));
deltaf = 1 / T;
kn = ceil(Doppler / (deltaf / N));
Ydd = circshift(Xdd, [lt kn]);
ydd = Ydd(:);
end
