Benchmark

Smoke benchmark run for documentation freshness. Run `mix bench` locally for stable measurements.

## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>macOS</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">Apple M2</td>
  </tr><tr>
    <th style="white-space: nowrap">Number of Available Cores</th>
    <td style="white-space: nowrap">8</td>
  </tr><tr>
    <th style="white-space: nowrap">Available Memory</th>
    <td style="white-space: nowrap">8 GB</td>
  </tr><tr>
    <th style="white-space: nowrap">Elixir Version</th>
    <td style="white-space: nowrap">1.19.4</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">28.4.2</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">10 ms</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">0 ns</td>
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
    <td style="white-space: nowrap; text-align: right">6452.25</td>
    <td style="white-space: nowrap; text-align: right">0.155 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;163.57%</td>
    <td style="white-space: nowrap; text-align: right">0.120 ms</td>
    <td style="white-space: nowrap; text-align: right">2.17 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.08 validate request across 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">1720.90</td>
    <td style="white-space: nowrap; text-align: right">0.58 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.17%</td>
    <td style="white-space: nowrap; text-align: right">0.56 ms</td>
    <td style="white-space: nowrap; text-align: right">0.83 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.15 availability eligible pool request</td>
    <td style="white-space: nowrap; text-align: right">1698.00</td>
    <td style="white-space: nowrap; text-align: right">0.59 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.46%</td>
    <td style="white-space: nowrap; text-align: right">0.55 ms</td>
    <td style="white-space: nowrap; text-align: right">0.85 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.09 decide with assignment and alternatives</td>
    <td style="white-space: nowrap; text-align: right">1504.78</td>
    <td style="white-space: nowrap; text-align: right">0.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;51.70%</td>
    <td style="white-space: nowrap; text-align: right">0.56 ms</td>
    <td style="white-space: nowrap; text-align: right">1.89 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.12 rrule weekly byday 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">863.99</td>
    <td style="white-space: nowrap; text-align: right">1.16 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.47%</td>
    <td style="white-space: nowrap; text-align: right">1.16 ms</td>
    <td style="white-space: nowrap; text-align: right">1.27 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.11 rrule daily 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">844.70</td>
    <td style="white-space: nowrap; text-align: right">1.18 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;97.44%</td>
    <td style="white-space: nowrap; text-align: right">0.80 ms</td>
    <td style="white-space: nowrap; text-align: right">4.26 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.13 ics freebusy 500 periods</td>
    <td style="white-space: nowrap; text-align: right">538.67</td>
    <td style="white-space: nowrap; text-align: right">1.86 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;25.09%</td>
    <td style="white-space: nowrap; text-align: right">1.70 ms</td>
    <td style="white-space: nowrap; text-align: right">2.80 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.14 jscalendar group 500 events</td>
    <td style="white-space: nowrap; text-align: right">443.50</td>
    <td style="white-space: nowrap; text-align: right">2.25 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.43%</td>
    <td style="white-space: nowrap; text-align: right">2.04 ms</td>
    <td style="white-space: nowrap; text-align: right">2.92 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.01 interval merge 2k intervals</td>
    <td style="white-space: nowrap; text-align: right">370.80</td>
    <td style="white-space: nowrap; text-align: right">2.70 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.31%</td>
    <td style="white-space: nowrap; text-align: right">2.71 ms</td>
    <td style="white-space: nowrap; text-align: right">2.91 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.03 slotting 8 week free interval</td>
    <td style="white-space: nowrap; text-align: right">188.24</td>
    <td style="white-space: nowrap; text-align: right">5.31 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.21%</td>
    <td style="white-space: nowrap; text-align: right">5.31 ms</td>
    <td style="white-space: nowrap; text-align: right">5.77 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.05 availability one host 8 weeks</td>
    <td style="white-space: nowrap; text-align: right">142.73</td>
    <td style="white-space: nowrap; text-align: right">7.01 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;30.71%</td>
    <td style="white-space: nowrap; text-align: right">7.01 ms</td>
    <td style="white-space: nowrap; text-align: right">8.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.06 availability collective 10 hosts</td>
    <td style="white-space: nowrap; text-align: right">131.00</td>
    <td style="white-space: nowrap; text-align: right">7.63 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.70%</td>
    <td style="white-space: nowrap; text-align: right">7.63 ms</td>
    <td style="white-space: nowrap; text-align: right">7.78 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.10 assignment weighted 1k resources</td>
    <td style="white-space: nowrap; text-align: right">44.61</td>
    <td style="white-space: nowrap; text-align: right">22.42 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">22.42 ms</td>
    <td style="white-space: nowrap; text-align: right">22.42 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.02 interval subtract 1k busy intervals</td>
    <td style="white-space: nowrap; text-align: right">7.35</td>
    <td style="white-space: nowrap; text-align: right">136.14 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">136.14 ms</td>
    <td style="white-space: nowrap; text-align: right">136.14 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.07 availability pool 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">1.87</td>
    <td style="white-space: nowrap; text-align: right">535.25 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">535.25 ms</td>
    <td style="white-space: nowrap; text-align: right">535.25 ms</td>
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
    <td style="white-space: nowrap;text-align: right">6452.25</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.08 validate request across 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">1720.90</td>
    <td style="white-space: nowrap; text-align: right">3.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.15 availability eligible pool request</td>
    <td style="white-space: nowrap; text-align: right">1698.00</td>
    <td style="white-space: nowrap; text-align: right">3.8x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.09 decide with assignment and alternatives</td>
    <td style="white-space: nowrap; text-align: right">1504.78</td>
    <td style="white-space: nowrap; text-align: right">4.29x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.12 rrule weekly byday 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">863.99</td>
    <td style="white-space: nowrap; text-align: right">7.47x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.11 rrule daily 500 occurrences</td>
    <td style="white-space: nowrap; text-align: right">844.70</td>
    <td style="white-space: nowrap; text-align: right">7.64x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.13 ics freebusy 500 periods</td>
    <td style="white-space: nowrap; text-align: right">538.67</td>
    <td style="white-space: nowrap; text-align: right">11.98x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.14 jscalendar group 500 events</td>
    <td style="white-space: nowrap; text-align: right">443.50</td>
    <td style="white-space: nowrap; text-align: right">14.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.01 interval merge 2k intervals</td>
    <td style="white-space: nowrap; text-align: right">370.80</td>
    <td style="white-space: nowrap; text-align: right">17.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.03 slotting 8 week free interval</td>
    <td style="white-space: nowrap; text-align: right">188.24</td>
    <td style="white-space: nowrap; text-align: right">34.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.05 availability one host 8 weeks</td>
    <td style="white-space: nowrap; text-align: right">142.73</td>
    <td style="white-space: nowrap; text-align: right">45.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.06 availability collective 10 hosts</td>
    <td style="white-space: nowrap; text-align: right">131.00</td>
    <td style="white-space: nowrap; text-align: right">49.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.10 assignment weighted 1k resources</td>
    <td style="white-space: nowrap; text-align: right">44.61</td>
    <td style="white-space: nowrap; text-align: right">144.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.02 interval subtract 1k busy intervals</td>
    <td style="white-space: nowrap; text-align: right">7.35</td>
    <td style="white-space: nowrap; text-align: right">878.41x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">BK.07 availability pool 100 hosts</td>
    <td style="white-space: nowrap; text-align: right">1.87</td>
    <td style="white-space: nowrap; text-align: right">3453.58x</td>
  </tr>

</table>