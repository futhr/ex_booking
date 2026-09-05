Benchmark

Full benchmark run (2s warmup, 5s measurement, 1s memory per scenario). Input construction is included. Memory means cumulative process allocations, including garbage-collected memory. Results describe distinct workloads on the recorded machine; cross-scenario ratios are not before/after speedups.

## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>macOS</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">Apple M5 Pro</td>
  </tr><tr>
    <th style="white-space: nowrap">Number of Available Cores</th>
    <td style="white-space: nowrap">18</td>
  </tr><tr>
    <th style="white-space: nowrap">Available Memory</th>
    <td style="white-space: nowrap">48 GB</td>
  </tr><tr>
    <th style="white-space: nowrap">Elixir Version</th>
    <td style="white-space: nowrap">1.18.4</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">28.5</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">5 s</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">2 s</td>
  </tr>
</table>

## Statistics



Run Time

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Deviation</th>
    <th style="text-align: right">Median</th>
    <th style="text-align: right">99th&nbsp;%</th>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.04 schedule expand 12 week business hours</td>
    <td style="white-space: nowrap; text-align: right">11135.83</td>
    <td style="white-space: nowrap; text-align: right">0.0898 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.52%</td>
    <td style="white-space: nowrap; text-align: right">0.0833 ms</td>
    <td style="white-space: nowrap; text-align: right">0.144 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.11 rrule daily 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">1462.72</td>
    <td style="white-space: nowrap; text-align: right">0.68 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.59%</td>
    <td style="white-space: nowrap; text-align: right">0.67 ms</td>
    <td style="white-space: nowrap; text-align: right">0.97 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.12 rrule weekly byday 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">1438.24</td>
    <td style="white-space: nowrap; text-align: right">0.70 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.52%</td>
    <td style="white-space: nowrap; text-align: right">0.66 ms</td>
    <td style="white-space: nowrap; text-align: right">1.05 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.15 availability eligible pool request</td>
    <td style="white-space: nowrap; text-align: right">1220.65</td>
    <td style="white-space: nowrap; text-align: right">0.82 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.17%</td>
    <td style="white-space: nowrap; text-align: right">0.81 ms</td>
    <td style="white-space: nowrap; text-align: right">0.96 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.09 decide accepted request with assignment</td>
    <td style="white-space: nowrap; text-align: right">1200.51</td>
    <td style="white-space: nowrap; text-align: right">0.83 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.82%</td>
    <td style="white-space: nowrap; text-align: right">0.82 ms</td>
    <td style="white-space: nowrap; text-align: right">1.01 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.08 validate request across 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">1191.48</td>
    <td style="white-space: nowrap; text-align: right">0.84 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.99%</td>
    <td style="white-space: nowrap; text-align: right">0.81 ms</td>
    <td style="white-space: nowrap; text-align: right">1.28 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.13 ics freebusy 500 periods</td>
    <td style="white-space: nowrap; text-align: right">851.14</td>
    <td style="white-space: nowrap; text-align: right">1.17 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.20%</td>
    <td style="white-space: nowrap; text-align: right">1.17 ms</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.02 interval subtract 1k busy intervals</td>
    <td style="white-space: nowrap; text-align: right">706.46</td>
    <td style="white-space: nowrap; text-align: right">1.42 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.61%</td>
    <td style="white-space: nowrap; text-align: right">1.37 ms</td>
    <td style="white-space: nowrap; text-align: right">1.71 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.01 interval merge 2k intervals</td>
    <td style="white-space: nowrap; text-align: right">585.60</td>
    <td style="white-space: nowrap; text-align: right">1.71 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.26%</td>
    <td style="white-space: nowrap; text-align: right">1.61 ms</td>
    <td style="white-space: nowrap; text-align: right">2.42 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.05 availability one host 8 weeks</td>
    <td style="white-space: nowrap; text-align: right">480.90</td>
    <td style="white-space: nowrap; text-align: right">2.08 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.93%</td>
    <td style="white-space: nowrap; text-align: right">1.93 ms</td>
    <td style="white-space: nowrap; text-align: right">3.15 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.14 jscalendar group 500 events</td>
    <td style="white-space: nowrap; text-align: right">362.39</td>
    <td style="white-space: nowrap; text-align: right">2.76 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.68%</td>
    <td style="white-space: nowrap; text-align: right">2.74 ms</td>
    <td style="white-space: nowrap; text-align: right">3.11 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.06 availability collective 10 hosts</td>
    <td style="white-space: nowrap; text-align: right">311.21</td>
    <td style="white-space: nowrap; text-align: right">3.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.39%</td>
    <td style="white-space: nowrap; text-align: right">3.15 ms</td>
    <td style="white-space: nowrap; text-align: right">4.27 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.03 slotting 8 week free interval</td>
    <td style="white-space: nowrap; text-align: right">301.01</td>
    <td style="white-space: nowrap; text-align: right">3.32 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.32%</td>
    <td style="white-space: nowrap; text-align: right">3.21 ms</td>
    <td style="white-space: nowrap; text-align: right">4.68 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.10 assignment weighted 1k resources</td>
    <td style="white-space: nowrap; text-align: right">56.53</td>
    <td style="white-space: nowrap; text-align: right">17.69 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.86%</td>
    <td style="white-space: nowrap; text-align: right">16.63 ms</td>
    <td style="white-space: nowrap; text-align: right">29.20 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.07 availability pool 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">3.21</td>
    <td style="white-space: nowrap; text-align: right">311.31 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.27%</td>
    <td style="white-space: nowrap; text-align: right">310.46 ms</td>
    <td style="white-space: nowrap; text-align: right">325.58 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">BK.04 schedule expand 12 week business hours</td>
    <td style="white-space: nowrap;text-align: right">11135.83</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.11 rrule daily 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">1462.72</td>
    <td style="white-space: nowrap; text-align: right">7.61x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.12 rrule weekly byday 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">1438.24</td>
    <td style="white-space: nowrap; text-align: right">7.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.15 availability eligible pool request</td>
    <td style="white-space: nowrap; text-align: right">1220.65</td>
    <td style="white-space: nowrap; text-align: right">9.12x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.09 decide accepted request with assignment</td>
    <td style="white-space: nowrap; text-align: right">1200.51</td>
    <td style="white-space: nowrap; text-align: right">9.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.08 validate request across 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">1191.48</td>
    <td style="white-space: nowrap; text-align: right">9.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.13 ics freebusy 500 periods</td>
    <td style="white-space: nowrap; text-align: right">851.14</td>
    <td style="white-space: nowrap; text-align: right">13.08x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.02 interval subtract 1k busy intervals</td>
    <td style="white-space: nowrap; text-align: right">706.46</td>
    <td style="white-space: nowrap; text-align: right">15.76x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.01 interval merge 2k intervals</td>
    <td style="white-space: nowrap; text-align: right">585.60</td>
    <td style="white-space: nowrap; text-align: right">19.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.05 availability one host 8 weeks</td>
    <td style="white-space: nowrap; text-align: right">480.90</td>
    <td style="white-space: nowrap; text-align: right">23.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.14 jscalendar group 500 events</td>
    <td style="white-space: nowrap; text-align: right">362.39</td>
    <td style="white-space: nowrap; text-align: right">30.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.06 availability collective 10 hosts</td>
    <td style="white-space: nowrap; text-align: right">311.21</td>
    <td style="white-space: nowrap; text-align: right">35.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.03 slotting 8 week free interval</td>
    <td style="white-space: nowrap; text-align: right">301.01</td>
    <td style="white-space: nowrap; text-align: right">37.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.10 assignment weighted 1k resources</td>
    <td style="white-space: nowrap; text-align: right">56.53</td>
    <td style="white-space: nowrap; text-align: right">196.99x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.07 availability pool 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">3.21</td>
    <td style="white-space: nowrap; text-align: right">3466.69x</td>
  </tr>

</table>



Memory Usage

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Factor</th>
  </tr>
  <tr>
    <td style="white-space: nowrap">BK.04 schedule expand 12 week business hours</td>
    <td style="white-space: nowrap">0.185 MB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.11 rrule daily 500 occurrences</td>
    <td style="white-space: nowrap">1.56 MB</td>
    <td>8.47x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.12 rrule weekly byday 500 occurrences</td>
    <td style="white-space: nowrap">1.63 MB</td>
    <td>8.83x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.15 availability eligible pool request</td>
    <td style="white-space: nowrap">1.71 MB</td>
    <td>9.26x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.09 decide accepted request with assignment</td>
    <td style="white-space: nowrap">1.81 MB</td>
    <td>9.79x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.08 validate request across 100 hosts</td>
    <td style="white-space: nowrap">1.71 MB</td>
    <td>9.25x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.13 ics freebusy 500 periods</td>
    <td style="white-space: nowrap">3.65 MB</td>
    <td>19.75x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.02 interval subtract 1k busy intervals</td>
    <td style="white-space: nowrap">3.37 MB</td>
    <td>18.24x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.01 interval merge 2k intervals</td>
    <td style="white-space: nowrap">4.62 MB</td>
    <td>25.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.05 availability one host 8 weeks</td>
    <td style="white-space: nowrap">5.36 MB</td>
    <td>29.0x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.14 jscalendar group 500 events</td>
    <td style="white-space: nowrap">2.90 MB</td>
    <td>15.69x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.06 availability collective 10 hosts</td>
    <td style="white-space: nowrap">7.73 MB</td>
    <td>41.86x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.03 slotting 8 week free interval</td>
    <td style="white-space: nowrap">9.91 MB</td>
    <td>53.64x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.10 assignment weighted 1k resources</td>
    <td style="white-space: nowrap">42.47 MB</td>
    <td>229.91x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">BK.07 availability pool 100 hosts</td>
    <td style="white-space: nowrap">664.15 MB</td>
    <td>3595.38x</td>
  </tr>
</table>