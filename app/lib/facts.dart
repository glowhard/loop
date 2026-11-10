// Something worth knowing while a session starts. Kept in the app, so it costs
// nothing and works with no signal at all.
class Fact {
  const Fact(this.tag, this.title, this.body);
  final String tag;
  final String title;
  final String body;
}

const kFacts = <Fact>[
  // ---- how models work ----
  Fact(
    'AI',
    'Attention replaced memory',
    'Before 2017 language models read a sentence word by word, carrying a memory forward. "Attention Is All You Need" let every word look at every other word at once, which is what made training on today\'s scale possible.',
  ),
  Fact(
    'AI',
    'Why a context window has a limit',
    'With attention, every token is compared to every other token, so the work grows with the square of the length: twice the context is four times the work. The limit is arithmetic, not storage.',
  ),
  Fact(
    'AI',
    'Models do not see letters',
    'Text is cut into tokens first, so a word can be two or three pieces, and the model never sees the spelling. That is why counting the letters in a word is oddly hard for something that can write an essay about it.',
  ),
  Fact(
    'AI',
    'Temperature',
    'At temperature 0 a model always takes the most likely next token, which reads as flat and repetitive. Higher values sample from the rest of the distribution: more surprising, and more often wrong.',
  ),
  Fact(
    'AI',
    'Why models make things up',
    'A language model is trained to continue text plausibly, not to be right. A confident wrong answer and a confident right one are produced by exactly the same machinery, which is why checking matters.',
  ),
  Fact(
    'AI',
    'Retrieval beats remembering',
    'Facts baked into weights are expensive to change and easy to garble. Looking the fact up and putting it in the prompt is cheaper, newer, and can be checked — the idea behind retrieval-augmented generation.',
  ),
  Fact(
    'AI',
    'The Chinchilla correction',
    'In 2022 DeepMind showed most large models were undertrained: for a given budget, a smaller model fed far more data beats a bigger model fed less. Size alone had been the wrong thing to chase.',
  ),
  Fact(
    'AI',
    'The bitter lesson',
    'Rich Sutton\'s observation from 70 years of AI: methods that simply scale with computing power keep beating methods built on hand-crafted human knowledge, however satisfying the latter feel.',
  ),
  Fact(
    'AI',
    'Embeddings',
    'Words become vectors, placed so that similar meanings land near each other. Search stops being about matching letters and becomes about measuring distance.',
  ),
  Fact(
    'AI',
    'Mixture of experts',
    'A model can hold many specialised sub-networks and run only two or three of them per token. Hundreds of billions of parameters, a fraction of the work for each word.',
  ),
  Fact(
    'AI',
    'Backpropagation is just the chain rule',
    'Popularised in 1986, the trick is schoolroom calculus applied at scale: work out how much each weight contributed to the error, and nudge it the other way.',
  ),
  Fact(
    'AI',
    'AlexNet ran on two gaming cards',
    'The 2012 result that started the deep learning boom was trained on a pair of consumer GeForce GTX 580s, because matrix multiplication happens to be exactly what a graphics card is built for.',
  ),
  Fact(
    'AI',
    'bfloat16',
    'Half-precision floats were too small in range for training. bfloat16 keeps the full exponent range of a 32-bit float and throws away precision instead, which neural networks barely notice.',
  ),

  // ---- the craft ----
  Fact(
    'Code',
    'The first bug was a moth',
    'In 1947 Grace Hopper\'s team at Harvard taped one into the Mark II logbook: "First actual case of bug being found." The word for a fault was already old — Edison used it in 1878 — but the moth is still in the book.',
  ),
  Fact(
    'Code',
    'Why 0.1 + 0.2 is not 0.3',
    'In binary, 0.1 is a repeating fraction, exactly as 1/3 is in decimal. The computer stores the nearest value it can, and the tiny error shows up when you add it to another one.',
  ),
  Fact(
    'Code',
    'The billion-dollar mistake',
    'Tony Hoare put the null reference into ALGOL W in 1965 "simply because it was so easy to implement", and later called it his billion-dollar mistake. Sixty years of crashes have followed.',
  ),
  Fact(
    'Code',
    'Quicksort came from translating Russian',
    'Hoare invented it in 1959 while working on machine translation: he needed to sort words to look them up in a dictionary, and the obvious method was too slow.',
  ),
  Fact(
    'Code',
    'Dijkstra had no pencil',
    'He worked out the shortest-path algorithm in about twenty minutes in 1956, sitting in an Amsterdam café with his fiancée and nothing to write on — which, he said, is why it came out simple enough to remember.',
  ),
  Fact(
    'Code',
    'The first programmer wrote hers in 1843',
    'Ada Lovelace\'s notes on Babbage\'s Analytical Engine include a step-by-step method for computing Bernoulli numbers, written for a machine that was never built.',
  ),
  Fact(
    'Code',
    'Some things cannot be computed',
    'Turing proved in 1936 that no program can look at every program and say whether it will finish or run forever. It is not a matter of being clever enough; the task is impossible.',
  ),
  Fact(
    'Code',
    'Endianness is a joke from Gulliver',
    'Big-endian and little-endian are named after the factions in Swift who go to war over which end of a boiled egg to crack. The 1980 paper that borrowed the name was about exactly that kind of argument.',
  ),
  Fact(
    'Code',
    'UTF-8 was designed on a placemat',
    'Ken Thompson and Rob Pike worked it out over dinner in a New Jersey diner in 1992. It is backwards compatible with ASCII, needs no byte-order mark, and now carries almost all of the web.',
  ),
  Fact(
    'Code',
    'Regular expressions cannot parse HTML',
    'Nested tags need a memory of how deep you are, and a regular expression has none. It is not a matter of a cleverer pattern: the language is the wrong shape for the tool.',
  ),
  Fact(
    'Code',
    'Git took about ten days',
    'When BitKeeper withdrew its free licence in 2005, Linus Torvalds wrote his own version control from scratch; within days it was managing its own source code.',
  ),
  Fact(
    'Code',
    'Two hard things',
    'Phil Karlton: "There are only two hard things in Computer Science: cache invalidation and naming things." The usual follow-up is that the third is off-by-one errors.',
  ),
  Fact(
    'Code',
    'Rubber duck debugging',
    'Explaining your code aloud, line by line, to an inanimate object. It works because the bug is usually in the gap between what you think the code says and what it says.',
  ),
  Fact(
    'Code',
    'Technical debt is a metaphor about interest',
    'Ward Cunningham coined it in 1992, and the point is often missed: borrowing is fine, but you pay interest on every change you make until you clean it up.',
  ),

  // ---- how systems behave ----
  Fact(
    'Systems',
    'Conway\'s law',
    'A system\'s design ends up copying the communication structure of the organisation that built it. Four teams on a compiler will produce a four-pass compiler.',
  ),
  Fact(
    'Systems',
    'Brooks\'s law',
    'Adding people to a late software project makes it later. New arrivals must be taught, and everyone must now talk to everyone, which grows with the square of the team.',
  ),
  Fact(
    'Systems',
    'Hyrum\'s law',
    'With enough users, every observable behaviour of your system will be depended on by somebody — including the bugs, the timing, and the order of things you never promised.',
  ),
  Fact(
    'Systems',
    'Postel\'s law, and its critics',
    '"Be conservative in what you do, be liberal in what you accept." It built an interoperable internet, and it also let sloppy implementations survive long enough to become the standard.',
  ),
  Fact(
    'Systems',
    'Goodhart\'s law',
    'When a measure becomes a target, it stops being a good measure. Count lines of code and you get long code; count tickets closed and you get small tickets.',
  ),
  Fact(
    'Systems',
    'Amdahl\'s law',
    'If a tenth of a job cannot be parallelised, then even with infinite processors you can only ever be ten times faster. The serial part sets the ceiling.',
  ),
  Fact(
    'Systems',
    'CAP, more carefully',
    'When the network splits, you choose between answering with possibly stale data and refusing to answer. The rest of the time you can have both; the theorem is only about the split.',
  ),
  Fact(
    'Systems',
    'The two generals',
    'Two armies on opposite hills must attack together, but every messenger may be captured. No number of confirmations makes it certain — which is why networked systems retry rather than wait for proof.',
  ),
  Fact(
    'Systems',
    'Idempotency saves you',
    'If doing a thing twice is the same as doing it once, you can safely retry anything. It is the quietest and most useful property a networked operation can have.',
  ),
  Fact(
    'Systems',
    'Little\'s law',
    'Items in a queue equal arrival rate times time spent waiting. It holds for checkouts, hospital beds and thread pools alike, and needs no assumptions about the distribution.',
  ),

  // ---- speed and limits ----
  Fact(
    'Speed',
    'Latency has a floor made of physics',
    'Light in fibre travels about 200,000 km per second. London to New York and back cannot beat roughly 56 milliseconds, however good the hardware.',
  ),
  Fact(
    'Speed',
    'The numbers worth memorising',
    'L1 cache about a nanosecond, main memory a hundred, an SSD read a hundred microseconds, a round trip across an ocean a tenth of a second. Each step is roughly a thousand times slower than the last.',
  ),
  Fact(
    'Speed',
    'Base64 costs a third',
    'Three bytes become four characters, so anything sent as base64 grows by about 33%. Convenient, and the reason binary uploads are better sent as bytes.',
  ),
  Fact(
    'Speed',
    'The birthday paradox',
    'In a room of 23 people it is more likely than not that two share a birthday. The same mathematics explains why hash collisions appear far sooner than the size of the hash suggests.',
  ),
  Fact(
    'Speed',
    'Bloom filters trade truth for space',
    'A Bloom filter can tell you "definitely not here" or "probably here", in a few bits per item. Databases use them to skip reading files that cannot contain your key.',
  ),

  // ---- when it went wrong ----
  Fact(
    'History',
    'Ariane 5, thirty-seven seconds',
    'In 1996 a rocket destroyed itself because a 64-bit number was put into a 16-bit slot. The code was correct — for Ariane 4, whose flight path never produced a number that large.',
  ),
  Fact(
    'History',
    'The Therac-25',
    'A race condition in a radiation therapy machine gave patients massive overdoses in the 1980s. The hardware interlocks that would have caught it had been removed in favour of the software.',
  ),
  Fact(
    'History',
    'goto fail',
    'In 2014 a single duplicated line in Apple\'s TLS code skipped the check that a certificate matched the site. Every connection looked verified and none were.',
  ),
  Fact(
    'History',
    'Heartbleed',
    'A missing bounds check in OpenSSL let anyone ask a server for a reply longer than the question, and receive whatever happened to sit next to it in memory — keys included.',
  ),
  Fact(
    'History',
    'Mariner 1',
    'A rocket was destroyed in 1962 after a hand-copied guidance formula lost a single overbar, turning smoothed velocity into raw, jittery velocity that the computer tried to correct.',
  ),
  Fact(
    'History',
    'The year 2038',
    'Unix time counts seconds from 1 January 1970, and a signed 32-bit counter runs out on 19 January 2038. Plenty of embedded systems still count that way.',
  ),
  Fact(
    'History',
    'The Morris worm',
    'In 1988 a graduate student\'s experiment spread faster than intended and took down a large part of the early internet, mostly because it reinfected machines it had already visited.',
  ),
  Fact(
    'History',
    'Reflections on Trusting Trust',
    'Ken Thompson showed a compiler could be taught to insert a backdoor into a program, and into any compiler built from clean source — so reading the source proves nothing on its own.',
  ),
  Fact(
    'History',
    'The first message was "LO"',
    'In 1969 the first thing sent over ARPANET was meant to be "LOGIN". The system crashed after two letters, which makes for a better story anyway.',
  ),
  Fact(
    'History',
    'A coffee pot started the webcam',
    'Cambridge researchers pointed a camera at the shared coffee pot in 1991 so nobody would walk to an empty jug. In 1993 it went onto the web and became the first live camera on it.',
  ),
  Fact(
    'History',
    'The first domain name',
    'symbolics.com was registered on 15 March 1985. In the whole of that year, fewer than ten domains were registered.',
  ),

  // ---- security ----
  Fact(
    'Security',
    'Hashing is not encryption',
    'Encryption is meant to be undone with a key; a hash is meant never to be undone at all. Storing a password encrypted rather than hashed is a bug, not a precaution.',
  ),
  Fact(
    'Security',
    'Good password hashes are slow on purpose',
    'bcrypt, scrypt and argon2 are deliberately expensive, and tunable, so that an attacker with a stolen database has to spend real time and memory on every single guess.',
  ),
  Fact(
    'Security',
    'Public key cryptography was invented twice',
    'Diffie and Hellman published in 1976 and RSA followed in 1977. Researchers at GCHQ had found much the same thing years earlier, but it was classified until 1997.',
  ),
  Fact(
    'Security',
    'The padlock means less than people think',
    'It says the connection is encrypted and the certificate matches the address. It says nothing at all about whether the site is honest.',
  ),
  Fact(
    'Security',
    'SQL injection is older than most developers',
    'It was described publicly in 1998 and is still found in production today, for the same reason every time: data pasted into a query instead of passed beside it.',
  ),
];
